import 'dart:async';
import 'dart:convert';

import 'package:queuekit/queuekit.dart';

typedef EventSerializers =
    Map<
      String,
      ({
        Event<Object?> Function(Map<String, dynamic> json) fromJson,
        Map<String, dynamic> Function(Event<Object?> event) toJson,
      })
    >;

base class HydratedQueue extends Queue {
  HydratedQueue(
    super.startListenable, {
    required this.eventSerializers,
    required this.saveCurrentQueue,
    required this.saveRetryQueue,
    required this.hydrateCurrentQueue,
    required this.hydrateRetryQueue,
  });

  final EventSerializers eventSerializers;
  // Save callbacks may be synchronous or asynchronous.
  // ignore: avoid_futureor_void
  final FutureOr<void> Function(String data) saveCurrentQueue;
  // ignore: avoid_futureor_void
  final FutureOr<void> Function(String data) saveRetryQueue;
  final FutureOr<String?> Function() hydrateCurrentQueue;
  final FutureOr<String?> Function() hydrateRetryQueue;

  @override
  Future<void> add(Event event, {Iterable<Event> dependsOn = const []}) async {
    super.add(event, dependsOn: dependsOn);
    await _save();
  }

  @override
  Future<void> removeIndexFromCurrentQueue(int index) async {
    super.removeIndexFromCurrentQueue(index);
    await _save();
  }

  @override
  Future<void> addToRetryQueue(String id, Event event, Duration duration) async {
    super.addToRetryQueue(id, event, duration);
    await _save();
  }

  @override
  Future<void> removeFromRetryQueue(String id) async {
    super.removeFromRetryQueue(id);
    await _save();
  }

  Future<void> hydrate() async {
    final rawCurrentQueue = await hydrateCurrentQueue();
    if (rawCurrentQueue != null) {
      final currentQueue = jsonDecode(rawCurrentQueue) as List;
      for (final json in currentQueue.cast<Map<String, dynamic>>()) {
        final serializer = eventSerializers[json['type']];
        if (serializer == null) continue;
        final event = serializer.fromJson(json);
        _hydrateDependencies(event, json);
        this.currentQueue.add(event);
      }
    }

    final rawRetryQueue = await hydrateRetryQueue();
    if (rawRetryQueue != null) {
      final retryQueue = jsonDecode(rawRetryQueue) as Map<String, dynamic>;
      final skipped = <String>{};
      for (final MapEntry(:key, :value)
          in retryQueue.cast<String, Map<String, dynamic>>().entries) {
        final serializer = eventSerializers[value['type']];
        if (serializer == null) continue;
        final event = serializer.fromJson(value['event'] as Map<String, dynamic>);
        _hydrateDependencies(event, value);
        final nextExecutionTime = DateTime.parse(value['nextExecutionTime'] as String);
        final retryConfig = event.retryConfig;
        final exceededRetries =
            retryConfig != null && retryConfig.retryCount >= retryConfig.maxRetries;
        if (exceededRetries || (dependencies[key]?.any(skipped.contains) ?? false)) {
          skipped.add(key);
          dependencies.remove(key);
          continue;
        }
        final now = DateTime.now();
        if (nextExecutionTime.difference(now) <= Duration.zero) {
          currentQueue.add(event);
        } else {
          this.retryQueue[key] = (event: event, nextExecutionTime: nextExecutionTime);
        }
      }
      // Events that are waiting for a dependency do not get a timer of their own; they are
      // re-queued when the dependency is retried.
      for (final MapEntry(:key, value: (:event, :nextExecutionTime)) in this.retryQueue.entries) {
        if (dependencies[key]?.any(this.retryQueue.containsKey) ?? false) continue;
        addTimerForRetry(key, event, nextExecutionTime.difference(DateTime.now()));
      }
    }

    releaseUnblockedEvents();
  }

  void _hydrateDependencies(Event event, Map<String, dynamic> json) {
    final dependsOn = (json['dependsOn'] as List?)?.cast<String>();
    if (dependsOn == null || dependsOn.isEmpty) return;
    dependencies[event.id] = dependsOn.toSet();
  }

  Future<void> _save() async {
    final List<Map<String, dynamic>> currentQueueJson = [];
    for (final event in currentQueue) {
      final serializer = eventSerializers[event.type];
      if (serializer == null) continue;
      currentQueueJson.add({
        ...serializer.toJson(event),
        'id': event.id,
        'type': event.type,
        ..._dependsOnJson(event),
      });
    }
    final currentQueueString = jsonEncode(currentQueueJson);
    await saveCurrentQueue(currentQueueString);

    final Map<String, Map<String, dynamic>> retryQueueJson = {};
    for (final MapEntry(:key, :value) in retryQueue.entries) {
      final serializer = eventSerializers[value.event.type];
      if (serializer == null) continue;
      retryQueueJson[key] = {
        'type': value.event.type,
        'event': serializer.toJson(value.event),
        'nextExecutionTime': value.nextExecutionTime.toIso8601String(),
        ..._dependsOnJson(value.event),
      };
    }
    final retryQueueString = jsonEncode(retryQueueJson);
    await saveRetryQueue(retryQueueString);
  }

  Map<String, dynamic> _dependsOnJson(Event event) {
    final dependsOn = dependencies[event.id];
    if (dependsOn == null || dependsOn.isEmpty) return const {};
    return {'dependsOn': dependsOn.toList()};
  }
}
