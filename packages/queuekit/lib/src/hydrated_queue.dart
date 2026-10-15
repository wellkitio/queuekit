import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:queuekit/queuekit.dart';

/// A [Queue] that saves itself whenever it changes and restores itself with [hydrate].
///
/// The current queue and the retry queue are saved separately, as JSON strings, through
/// [saveCurrentQueue] and [saveRetryQueue], and read back through [hydrateCurrentQueue] and
/// [hydrateRetryQueue]. Changes made in the same synchronous run are saved together, and saves
/// are written one at a time, in order.
base class HydratedQueue extends Queue {
  /// Throws an [ArgumentError] if two of the [eventSerializers] have the same type.
  HydratedQueue(
    super.startListenable, {
    required Iterable<EventSerializer<Event<Object?>>> eventSerializers,
    required this.saveCurrentQueue,
    required this.saveRetryQueue,
    required this.hydrateCurrentQueue,
    required this.hydrateRetryQueue,
  }) {
    for (final serializer in eventSerializers) {
      if (_serializers.containsKey(serializer.type)) {
        throw ArgumentError.value(
          serializer.type,
          'eventSerializers',
          'has more than one serializer',
        );
      }
      _serializers[serializer.type] = serializer;
    }
  }

  final _serializers = <String, EventSerializer<Event<Object?>>>{};

  /// The serializers, by [Event.type]. Every event added to the queue must have one.
  Map<String, EventSerializer<Event<Object?>>> get eventSerializers =>
      UnmodifiableMapView(_serializers);

  /// Stores the serialized current queue. May be synchronous or asynchronous.
  // ignore: avoid_futureor_void
  final FutureOr<void> Function(String data) saveCurrentQueue;

  /// Stores the serialized retry queue. May be synchronous or asynchronous.
  // ignore: avoid_futureor_void
  final FutureOr<void> Function(String data) saveRetryQueue;

  /// Returns the last string passed to [saveCurrentQueue], or `null` if there is none.
  final FutureOr<String?> Function() hydrateCurrentQueue;

  /// Returns the last string passed to [saveRetryQueue], or `null` if there is none.
  final FutureOr<String?> Function() hydrateRetryQueue;

  Future<void>? _scheduledSave;
  Future<void> _pendingSaves = Future.value();

  /// Adds [event] and completes once the change is saved.
  ///
  /// Throws an [ArgumentError] if no serializer is registered for the event's type, or if the
  /// registered one is for another class. The future fails if a save callback throws; later saves
  /// are not affected.
  @override
  Future<void> add(Event event, {Iterable<Event> dependsOn = const []}) {
    _serializerFor(event);
    super.add(event, dependsOn: dependsOn);
    return _save();
  }

  @override
  Future<void> removeFromCurrentQueue(Event event) {
    super.removeFromCurrentQueue(event);
    return _save();
  }

  @override
  Future<void> addToRetryQueue(String id, Event event, DateTime nextExecutionTime) {
    super.addToRetryQueue(id, event, nextExecutionTime);
    return _save();
  }

  @override
  Future<void> removeFromRetryQueue(String id) {
    super.removeFromRetryQueue(id);
    return _save();
  }

  /// Restores the events saved by a previous instance.
  ///
  /// Call it once, before starting the queue, so restored events run before new ones. Retries
  /// whose time has come are placed on the current queue; the others wait for their turn. Saved
  /// events whose type has no serializer any more are dropped.
  Future<void> hydrate() async {
    final rawCurrentQueue = await hydrateCurrentQueue();
    if (rawCurrentQueue != null) {
      final entries = (jsonDecode(rawCurrentQueue) as List).cast<Map<String, dynamic>>();
      for (final json in entries) {
        final event = _eventFromJson(json['type'] as String?, json);
        if (event == null) continue;
        _hydrateDependencies(event, json);
        addToCurrentQueue(event);
      }
    }

    final rawRetryQueue = await hydrateRetryQueue();
    if (rawRetryQueue != null) {
      final entries = (jsonDecode(rawRetryQueue) as Map<String, dynamic>)
          .cast<String, Map<String, dynamic>>();
      final awaitingRetry = <String, bool?>{};
      for (final MapEntry(key: id, value: json) in entries.entries) {
        final event = _eventFromJson(
          json['type'] as String?,
          json['event'] as Map<String, dynamic>,
        );
        if (event == null) continue;
        _hydrateDependencies(event, json);
        final nextExecutionTime = DateTime.parse(json['nextExecutionTime'] as String);
        if (nextExecutionTime.isAfter(DateTime.now())) {
          super.addToRetryQueue(id, event, nextExecutionTime);
          awaitingRetry[id] = json['awaitingRetry'] as bool?;
        } else {
          addToCurrentQueue(event);
        }
      }
      // Events that are only waiting for a dependency do not get a timer of their own; they are
      // re-queued when the dependency is retried. Saves without the flag predate dependencies.
      for (final MapEntry(key: id, value: (:event, :nextExecutionTime)) in retryQueue.entries) {
        if (!(awaitingRetry[id] ?? !isWaitingForDependency(event))) continue;
        addTimerForRetry(id, event, nextExecutionTime.difference(DateTime.now()));
      }
    }

    // Drop dependencies on events that were not restored, for example because their type has no
    // serializer any more, so they are not persisted again.
    final pendingIds = pendingEvents.map((event) => event.id).toSet();
    dependencies.updateAll((_, ids) => ids..retainWhere(pendingIds.contains));
    dependencies.removeWhere((_, ids) => ids.isEmpty);

    releaseUnblockedEvents();
  }

  Event? _eventFromJson(String? type, Map<String, dynamic> json) {
    return _serializers[type]?.fromJson(json);
  }

  EventSerializer<Event<Object?>> _serializerFor(Event event) {
    final serializer = _serializers[event.type];
    if (serializer == null) {
      throw ArgumentError.value(
        event,
        'event',
        'has type "${event.type}", for which this queue has no EventSerializer',
      );
    }
    if (!serializer.accepts(event)) {
      throw ArgumentError.value(
        event,
        'event',
        'reports type "${event.type}", whose EventSerializer is for another class',
      );
    }
    return serializer;
  }

  void _hydrateDependencies(Event event, Map<String, dynamic> json) {
    final dependsOn = (json['dependsOn'] as List?)?.cast<String>();
    if (dependsOn == null || dependsOn.isEmpty) return;
    dependencies[event.id] = dependsOn.toSet();
  }

  /// Saves both queues once the current synchronous run of changes is over, after the saves that
  /// are already in flight, so that slow storage never persists an older state over a newer one.
  /// Returns the write, which fails if a save callback throws.
  Future<void> _save() {
    return _scheduledSave ??= Future.microtask(() {
      _scheduledSave = null;
      final currentQueueJson = _encodeCurrentQueue();
      final retryQueueJson = _encodeRetryQueue();
      final save = _pendingSaves.then((_) async {
        await saveCurrentQueue(currentQueueJson);
        await saveRetryQueue(retryQueueJson);
      });
      // A failed save surfaces to the caller but must not block the saves after it.
      _pendingSaves = save.catchError((Object _) {});
      return save;
    });
  }

  String _encodeCurrentQueue() {
    return jsonEncode([
      for (final event in currentQueue)
        {
          ..._serializerFor(event).toJson(event),
          'id': event.id,
          'type': event.type,
          ..._dependsOnJson(event),
        },
    ]);
  }

  String _encodeRetryQueue() {
    return jsonEncode({
      for (final MapEntry(key: id, value: (:event, :nextExecutionTime)) in retryQueue.entries)
        id: {
          'type': event.type,
          'event': _serializerFor(event).toJson(event),
          'nextExecutionTime': nextExecutionTime.toIso8601String(),
          'awaitingRetry': isAwaitingRetry(event),
          ..._dependsOnJson(event),
        },
    });
  }

  Map<String, dynamic> _dependsOnJson(Event event) {
    final dependsOn = dependencies[event.id];
    if (dependsOn == null || dependsOn.isEmpty) return const {};
    return {'dependsOn': dependsOn.toList()};
  }
}
