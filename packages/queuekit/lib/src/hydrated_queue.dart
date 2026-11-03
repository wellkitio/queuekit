import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:queuekit/queuekit.dart';

/// A [Queue] that saves itself whenever it changes and restores itself with [hydrate].
///
/// Persist events either per-record through a [QueueStore] ([HydratedQueue.store] or the [store]
/// parameter) or as whole-queue JSON snapshots through [saveCurrentQueue], [saveRetryQueue],
/// [hydrateCurrentQueue] and [hydrateRetryQueue].
///
/// Changes made in the same synchronous run are saved together in one atomic batch, and saves are
/// written one at a time, in order. An event never runs before its initial record is durable; if
/// saving that record fails, the future returned by [add] completes with the error and the event
/// waits at the head of the queue until a later save succeeds or [startListenable] is started
/// again.
base class HydratedQueue extends Queue {
  /// Creates a [HydratedQueue] backed either by a per-event [store] or by the snapshot callbacks
  /// [saveCurrentQueue], [saveRetryQueue], [hydrateCurrentQueue] and [hydrateRetryQueue].
  ///
  /// Throws an [ArgumentError] if two of the [eventSerializers] have the same type, or if neither
  /// [store] nor all four snapshot callbacks are provided.
  HydratedQueue(
    super.startListenable, {
    required Iterable<EventSerializer<Event<Object?>>> eventSerializers,
    this.store,
    this.saveCurrentQueue,
    this.saveRetryQueue,
    this.hydrateCurrentQueue,
    this.hydrateRetryQueue,
    this.retainFailedEvents = true,
    super.clock,
    super.retryPolicy,
  }) {
    _validateStorageConfig();
    _registerSerializers(eventSerializers);
  }

  /// Creates a [HydratedQueue] backed by a per-event [QueueStore].
  ///
  /// Throws an [ArgumentError] if two of the [eventSerializers] have the same type.
  HydratedQueue.store(
    super.startListenable, {
    required Iterable<EventSerializer<Event<Object?>>> eventSerializers,
    required QueueStore this.store,
    this.retainFailedEvents = true,
    super.clock,
    super.retryPolicy,
  }) : saveCurrentQueue = null,
       saveRetryQueue = null,
       hydrateCurrentQueue = null,
       hydrateRetryQueue = null {
    _registerSerializers(eventSerializers);
  }

  final _serializers = <String, EventSerializer<Event<Object?>>>{};

  /// The serializers, by [Event.type]. Every event added to the queue must have one.
  Map<String, EventSerializer<Event<Object?>>> get eventSerializers =>
      UnmodifiableMapView(_serializers);

  /// The per-event [QueueStore], or `null` when this queue uses snapshot callbacks.
  final QueueStore? store;

  /// Whether a store-backed queue keeps permanently failed events in [store] with
  /// [QueueRecordState.failed] by default instead of removing them.
  final bool retainFailedEvents;

  /// Stores the serialized current queue when using snapshot persistence.
  // ignore: avoid_futureor_void
  final FutureOr<void> Function(String data)? saveCurrentQueue;

  /// Stores the serialized retry queue when using snapshot persistence.
  // ignore: avoid_futureor_void
  final FutureOr<void> Function(String data)? saveRetryQueue;

  /// Returns the last string passed to [saveCurrentQueue], or `null` if there is none.
  final FutureOr<String?> Function()? hydrateCurrentQueue;

  /// Returns the last string passed to [saveRetryQueue], or `null` if there is none.
  final FutureOr<String?> Function()? hydrateRetryQueue;

  final _sequences = <String, int>{};
  final _knownIds = <String>{};
  final _persistedRecords = <String, QueueRecord>{};
  final _preparedRecords = <String, QueueRecord>{};
  final _pendingFailedRecords = <String, QueueRecord>{};
  final _durableIds = <String>{};

  final _unhydratedCurrentQueueJson = <Map<String, dynamic>>[];
  final _unhydratedRetryQueueJson = <String, Map<String, dynamic>>{};

  int _nextSequence = 0;
  bool _hydrating = false;
  bool _hasFailedSave = false;

  Future<void>? _scheduledSave;
  Future<void> _pendingSaves = Future.value();

  /// Builds the [QueueRecord] for [event] so the caller can persist it inside its own database
  /// transaction before calling [add] with `persisted: true`.
  ///
  /// If the caller's transaction rolls back without calling [add], call [discardRecord] with
  /// `event.id` to release the prepared record.
  ///
  /// Throws an [ArgumentError] if no serializer is registered for the event's type, or if the
  /// registered one is for another class.
  QueueRecord recordFor(Event event, {Iterable<Event> dependsOn = const []}) {
    final serializer = _serializerFor(event);
    final dependencyIds = <String>{
      if (dependencies[event.id] case final existing?) ...existing,
      for (final dependency in dependsOn)
        if (dependency.id != event.id &&
            (findEvent(dependency.id) != null || _preparedRecords.containsKey(dependency.id)))
          dependency.id,
    };
    DateTime? blockedUntil;
    for (final id in dependencyIds) {
      final entry = retryQueue[id];
      if (entry == null) continue;
      if (blockedUntil == null || entry.nextExecutionTime.isAfter(blockedUntil)) {
        blockedUntil = entry.nextExecutionTime;
      }
    }
    final sequence = findEvent(event.id) != null
        ? (_sequences[event.id] ??= ++_nextSequence)
        : (_preparedRecords[event.id]?.sequence ?? ++_nextSequence);
    final attemptCount = attemptCounts[event.id] ?? event.retryConfig?.retryCount ?? 0;
    final record = QueueRecord(
      id: event.id,
      type: event.type,
      eventJson: serializer.toJson(event),
      state: blockedUntil != null ? QueueRecordState.scheduled : QueueRecordState.pending,
      dependsOn: dependencyIds,
      attemptCount: attemptCount,
      nextAttemptAt: blockedUntil,
      sequence: sequence,
    );
    _preparedRecords[event.id] = record;
    return record;
  }

  /// Discards a [QueueRecord] previously prepared by [recordFor] when the caller's database
  /// transaction rolls back before [add] is called.
  void discardRecord(String id) {
    if (_preparedRecords.remove(id) == null) return;
    dependencies.updateAll((_, ids) => ids..remove(id));
    dependencies.removeWhere((_, ids) => ids.isEmpty);
    resumeProcessing();
  }

  /// Adds [event] and completes once the change is saved.
  ///
  /// Pass `persisted: true` when the event's [QueueRecord] (from [recordFor]) has already been
  /// written to [store] inside the caller's own transaction. The queue then skips inserting the
  /// record again unless the event's state or ordering changed before [add] was called.
  ///
  /// Throws an [ArgumentError] if no serializer is registered for the event's type, if the
  /// registered one is for another class, or if `persisted: true` is passed when [store] is `null`.
  /// The future fails if a save callback or [QueueStore.apply] throws; later saves are not
  /// affected, and an event whose initial save failed waits at the head of the queue until a later
  /// save succeeds or [startListenable] is started again.
  @override
  Future<void> add(Event event, {Iterable<Event> dependsOn = const [], bool persisted = false}) {
    _serializerFor(event);
    if (persisted && store == null) {
      throw ArgumentError.value(persisted, 'persisted', 'requires a QueueStore');
    }
    var effectiveDependsOn = dependsOn;
    final prepared = persisted ? _preparedRecords.remove(event.id) : null;
    if (prepared != null) {
      if (prepared.dependsOn.isNotEmpty) {
        effectiveDependsOn = <Event>[
          ...dependsOn,
          for (final id in prepared.dependsOn)
            if (findEvent(id) case final dep?) dep,
        ];
        final pendingPreparedDeps = <String>{
          for (final id in prepared.dependsOn)
            if (id != event.id && (findEvent(id) != null || _preparedRecords.containsKey(id))) id,
        };
        if (pendingPreparedDeps.isNotEmpty) {
          dependencies.update(
            event.id,
            (ids) => ids..addAll(pendingPreparedDeps),
            ifAbsent: () => pendingPreparedDeps,
          );
        }
      }
      _knownIds.add(event.id);
      _persistedRecords[event.id] = prepared;
      _durableIds.add(event.id);
      _sequences[event.id] = prepared.sequence;
    } else {
      _preparedRecords.remove(event.id);
      if (!attemptCounts.containsKey(event.id)) {
        _sequences.remove(event.id);
      }
      _knownIds.add(event.id);
    }
    super.add(event, dependsOn: effectiveDependsOn);
    if (prepared != null &&
        store != null &&
        !_hasFailedSave &&
        _pendingFailedRecords.isEmpty &&
        _currentRecordFor(event.id) == prepared) {
      resumeProcessing();
      return Future<void>.value();
    }
    return _save();
  }

  @override
  void addToCurrentQueue(Event event) {
    _knownIds.add(event.id);
    if (!_hydrating) {
      _sequences[event.id] ??= ++_nextSequence;
    }
    super.addToCurrentQueue(event);
  }

  @override
  Future<void> removeFromCurrentQueue(Event event) {
    super.removeFromCurrentQueue(event);
    return _save();
  }

  @override
  Future<void> addToRetryQueue(String id, Event event, DateTime nextExecutionTime) {
    _knownIds.add(id);
    if (!_hydrating) {
      _sequences[id] ??= ++_nextSequence;
    }
    super.addToRetryQueue(id, event, nextExecutionTime);
    return _save();
  }

  @override
  Future<void> removeFromRetryQueue(String id) {
    super.removeFromRetryQueue(id);
    return _save();
  }

  @override
  Future<void> beforeRun(Event event) async {
    await _pendingSaves;
    if (!canRun(event) || _scheduledSave != null || _hasFailedSave) {
      await _save().catchError((Object _) {});
    }
  }

  @override
  bool canRun(Event event) {
    if (_hydrating || !_durableIds.contains(event.id)) return false;
    if (hasUnaddedDependency(event)) return false;
    final deps = dependencies[event.id];
    if (deps != null && deps.any((id) => findEvent(id) != null)) {
      return false;
    }
    return true;
  }

  @override
  bool hasUnaddedDependency(Event event) {
    final visited = <String>{};
    bool check(Set<String>? ids) {
      if (ids == null) return false;
      for (final id in ids) {
        if (!visited.add(id)) continue;
        if (_preparedRecords.containsKey(id)) return true;
        if (check(dependencies[id])) return true;
      }
      return false;
    }

    return check(dependencies[event.id]);
  }

  @override
  void onEventPaused(Event event) {
    _save();
  }

  @override
  void onEventFailedPermanently(Event event, Object error, {required bool? retainRecord}) {
    if (store == null) return;
    final shouldRetain = retainRecord ?? retainFailedEvents;
    if (shouldRetain) {
      _pendingFailedRecords[event.id] = _buildRecord(
        event,
        state: QueueRecordState.failed,
        error: error.toString(),
      );
    } else {
      _pendingFailedRecords.remove(event.id);
    }
  }

  /// Restores the events saved by a previous instance, optionally narrowed to those matching
  /// [filter].
  ///
  /// Call it once, before starting the queue, so restored events run before new ones. Retries
  /// whose time has come (according to [clock]) are placed on the current queue; the others wait
  /// for their turn. Records with [QueueRecordState.failed] are terminal and are not restored.
  /// Saved events whose type has no serializer any more are dropped.
  Future<void> hydrate({QueueRecordFilter? filter}) async {
    _hydrating = true;
    try {
      if (store != null) {
        await _hydrateFromStore(filter: filter);
      } else {
        await _hydrateFromSnapshots(filter: filter);
      }

      // Drop dependencies on events that were not restored, for example because their type has no
      // serializer any more or they did not match the filter, so they are not persisted again.
      final pendingIds = pendingEvents.map((event) => event.id).toSet();
      dependencies.updateAll((_, ids) => ids..retainWhere(pendingIds.contains));
      dependencies.removeWhere((_, ids) => ids.isEmpty);

      releaseUnblockedEvents();
      for (final event in pendingEvents) {
        _durableIds.add(event.id);
        _knownIds.add(event.id);
      }
      _hydrating = false;
      resumeProcessing();
    } finally {
      _hydrating = false;
    }
  }

  Future<void> _hydrateFromStore({QueueRecordFilter? filter}) async {
    final loaded = (await store!.load(filter: filter)).toList()..sort(_compareRecords);
    for (final record in loaded) {
      if (record.sequence > _nextSequence) {
        _nextSequence = record.sequence;
      }
    }
    if (filter != null) {
      final storeMax = await store!.maxSequence();
      if (storeMax > _nextSequence) {
        _nextSequence = storeMax;
      }
    }
    final filtered = filter == null ? loaded : loaded.where(filter).toList();
    final awaitingRetry = <String, bool>{};
    final now = clock.now();

    for (final record in filtered) {
      _persistedRecords[record.id] = record;
      if (record.state == QueueRecordState.failed) continue;
      final event = _eventFromJson(record.type, record.eventJson);
      _knownIds.add(record.id);
      if (event == null) continue;
      _restoreRecordMetadata(event, record);
      if (record.state == QueueRecordState.scheduled) {
        final nextAttemptAt = record.nextAttemptAt;
        if (nextAttemptAt != null && nextAttemptAt.isAfter(now)) {
          super.addToRetryQueue(record.id, event, nextAttemptAt);
          awaitingRetry[record.id] = record.awaitingRetry;
          continue;
        }
      }
      addToCurrentQueue(event);
    }

    final timerNow = clock.now();
    for (final MapEntry(key: id, value: (:event, :nextExecutionTime)) in retryQueue.entries) {
      if (!(awaitingRetry[id] ?? !isWaitingForDependency(event))) continue;
      final delay = nextExecutionTime.isAfter(timerNow)
          ? nextExecutionTime.difference(timerNow)
          : Duration.zero;
      addTimerForRetry(id, event, delay);
    }
  }

  Future<void> _hydrateFromSnapshots({QueueRecordFilter? filter}) async {
    _unhydratedCurrentQueueJson.clear();
    _unhydratedRetryQueueJson.clear();
    final rawCurrentQueue = await hydrateCurrentQueue!();
    if (rawCurrentQueue != null) {
      final entries = (jsonDecode(rawCurrentQueue) as List).cast<Map<String, dynamic>>();
      for (final json in entries) {
        final type = json['type'] as String?;
        final event = _eventFromJson(type, json);
        if (event == null) continue;
        final sequence = ++_nextSequence;
        final dependsOn = (json['dependsOn'] as List?)?.cast<String>() ?? const <String>[];
        if (filter != null) {
          final record = QueueRecord(
            id: event.id,
            type: event.type,
            eventJson: json,
            dependsOn: dependsOn,
            attemptCount: event.retryConfig?.retryCount ?? 0,
            sequence: sequence,
          );
          if (!filter(record)) {
            _unhydratedCurrentQueueJson.add(json);
            continue;
          }
        }
        _sequences[event.id] = sequence;
        attemptCounts[event.id] = event.retryConfig?.retryCount ?? 0;
        _hydrateDependencies(event, json);
        addToCurrentQueue(event);
      }
    }

    final rawRetryQueue = await hydrateRetryQueue!();
    if (rawRetryQueue != null) {
      final entries = (jsonDecode(rawRetryQueue) as Map<String, dynamic>)
          .cast<String, Map<String, dynamic>>();
      final awaitingRetry = <String, bool?>{};
      final now = clock.now();
      for (final MapEntry(key: id, value: json) in entries.entries) {
        final eventJson = json['event'] as Map<String, dynamic>;
        final event = _eventFromJson(json['type'] as String?, eventJson);
        if (event == null) continue;
        final sequence = ++_nextSequence;
        final nextExecutionTime = DateTime.parse(json['nextExecutionTime'] as String);
        final isAwaiting = json['awaitingRetry'] as bool?;
        final dependsOn = (json['dependsOn'] as List?)?.cast<String>() ?? const <String>[];
        if (filter != null) {
          final record = QueueRecord(
            id: id,
            type: event.type,
            eventJson: eventJson,
            state: QueueRecordState.scheduled,
            dependsOn: dependsOn,
            attemptCount: event.retryConfig?.retryCount ?? 0,
            nextAttemptAt: nextExecutionTime,
            awaitingRetry: isAwaiting ?? true,
            sequence: sequence,
          );
          if (!filter(record)) {
            _unhydratedRetryQueueJson[id] = json;
            continue;
          }
        }
        _sequences[event.id] = sequence;
        attemptCounts[event.id] = event.retryConfig?.retryCount ?? 0;
        _hydrateDependencies(event, json);
        if (nextExecutionTime.isAfter(now)) {
          super.addToRetryQueue(id, event, nextExecutionTime);
          awaitingRetry[id] = isAwaiting;
        } else {
          addToCurrentQueue(event);
        }
      }
      // Events that are only waiting for a dependency do not get a timer of their own; they are
      // re-queued when the dependency is retried. Saves without the flag predate dependencies.
      final timerNow = clock.now();
      for (final MapEntry(key: id, value: (:event, :nextExecutionTime)) in retryQueue.entries) {
        if (!(awaitingRetry[id] ?? !isWaitingForDependency(event))) continue;
        final delay = nextExecutionTime.isAfter(timerNow)
            ? nextExecutionTime.difference(timerNow)
            : Duration.zero;
        addTimerForRetry(id, event, delay);
      }
    }
  }

  void _restoreRecordMetadata(Event event, QueueRecord record) {
    _sequences[event.id] = record.sequence;
    attemptCounts[event.id] = record.attemptCount;
    final retryConfig = event.retryConfig;
    if (record.state == QueueRecordState.scheduled &&
        record.awaitingRetry &&
        retryConfig != null &&
        retryConfig.maxRetries >= 0 &&
        retryConfig.retryCount == 0 &&
        record.attemptCount > 0) {
      retryConfig.retryCount = record.attemptCount;
    }
    if (record.dependsOn.isNotEmpty) {
      dependencies[event.id] = record.dependsOn.toSet();
    }
  }

  void _validateStorageConfig() {
    final hasStore = store != null;
    final hasAllCallbacks =
        saveCurrentQueue != null &&
        saveRetryQueue != null &&
        hydrateCurrentQueue != null &&
        hydrateRetryQueue != null;
    final hasAnyCallback =
        saveCurrentQueue != null ||
        saveRetryQueue != null ||
        hydrateCurrentQueue != null ||
        hydrateRetryQueue != null;
    if (hasStore && hasAnyCallback) {
      throw ArgumentError('Provide either store or the snapshot callbacks, not both.');
    }
    if (!hasStore && !hasAllCallbacks) {
      throw ArgumentError(
        'Provide either store or all four snapshot callbacks '
        '(saveCurrentQueue, saveRetryQueue, hydrateCurrentQueue, hydrateRetryQueue).',
      );
    }
  }

  void _registerSerializers(Iterable<EventSerializer<Event<Object?>>> eventSerializers) {
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

  QueueRecord? _currentRecordFor(String id) {
    for (final event in currentQueue) {
      if (event.id == id) {
        return _buildRecord(event, state: QueueRecordState.pending);
      }
    }
    if (retryQueue[id] case (:final event, :final nextExecutionTime)) {
      return _buildRecord(
        event,
        state: QueueRecordState.scheduled,
        nextAttemptAt: nextExecutionTime,
        awaitingRetry: isAwaitingRetry(event),
      );
    }
    return null;
  }

  QueueRecord _buildRecord(
    Event event, {
    required QueueRecordState state,
    DateTime? nextAttemptAt,
    bool awaitingRetry = false,
    String? error,
  }) {
    final serializer = _serializerFor(event);
    final dependsOn = dependencies[event.id] ?? const <String>{};
    final sequence = _sequences[event.id] ??= ++_nextSequence;
    final attemptCount = attemptCounts[event.id] ?? event.retryConfig?.retryCount ?? 0;
    return QueueRecord(
      id: event.id,
      type: event.type,
      eventJson: serializer.toJson(event),
      state: state,
      dependsOn: dependsOn,
      attemptCount: attemptCount,
      nextAttemptAt: nextAttemptAt,
      awaitingRetry: awaitingRetry,
      sequence: sequence,
      error: error,
    );
  }

  ({
    Map<String, QueueRecord> activeRecords,
    Map<String, QueueRecord> failedRecords,
    Set<String> removedIds,
  })
  _peekTargetStoreState() {
    final activeRecords = <String, QueueRecord>{
      for (final event in currentQueue)
        event.id: _buildRecord(event, state: QueueRecordState.pending),
      for (final MapEntry(key: id, value: (:event, :nextExecutionTime)) in retryQueue.entries)
        id: _buildRecord(
          event,
          state: QueueRecordState.scheduled,
          nextAttemptAt: nextExecutionTime,
          awaitingRetry: isAwaitingRetry(event),
        ),
    };
    final failedRecords = <String, QueueRecord>{
      for (final MapEntry(:key, :value) in _pendingFailedRecords.entries)
        if (!activeRecords.containsKey(key)) key: value,
    };
    final removedIds = <String>{
      for (final id in _knownIds)
        if (!activeRecords.containsKey(id) && !failedRecords.containsKey(id)) id,
    };
    return (activeRecords: activeRecords, failedRecords: failedRecords, removedIds: removedIds);
  }

  ({
    Map<String, QueueRecord> activeRecords,
    Map<String, QueueRecord> failedRecords,
    Set<String> removedIds,
    Map<String, int> releasedSequences,
  })
  _consumeTargetStoreState() {
    final (:activeRecords, :failedRecords, :removedIds) = _peekTargetStoreState();
    _pendingFailedRecords.clear();
    _knownIds
      ..removeAll(removedIds)
      ..removeAll(failedRecords.keys);
    final releasedSequences = <String, int>{};
    for (final id in removedIds) {
      if (_sequences.remove(id) case final seq?) releasedSequences[id] = seq;
      _preparedRecords.remove(id);
    }
    for (final id in failedRecords.keys) {
      if (_sequences.remove(id) case final seq?) releasedSequences[id] = seq;
      _preparedRecords.remove(id);
    }
    return (
      activeRecords: activeRecords,
      failedRecords: failedRecords,
      removedIds: removedIds,
      releasedSequences: releasedSequences,
    );
  }

  List<QueueChange> _diffAgainstPersisted(
    Map<String, QueueRecord> activeRecords,
    Map<String, QueueRecord> failedRecords,
    Set<String> removedIds,
  ) {
    final changes = <QueueChange>[];
    for (final id in removedIds) {
      if (_persistedRecords.containsKey(id) && findEvent(id) == null) {
        changes.add(QueueRecordRemove(id));
      }
    }
    final orderedActive = activeRecords.values.toList()..sort(_compareRecords);
    for (final record in orderedActive) {
      final existing = _persistedRecords[record.id];
      if (existing == null) {
        changes.add(QueueRecordInsert(record));
      } else if (existing != record && existing.sequence <= record.sequence) {
        changes.add(QueueRecordUpdate(record));
      }
    }
    final orderedFailed = failedRecords.values.toList()..sort(_compareRecords);
    for (final record in orderedFailed) {
      final existing = _persistedRecords[record.id];
      if (existing == null) {
        changes.add(QueueRecordInsert(record));
      } else if (existing != record) {
        changes.add(QueueRecordUpdate(record));
      }
    }
    return changes;
  }

  /// Saves the queue once the current synchronous run of changes is over, after the saves that
  /// are already in flight, so that slow storage never persists an older state over a newer one.
  /// Returns the write, which fails if a save callback or [QueueStore.apply] throws.
  Future<void> _save() {
    return _scheduledSave ??= Future.microtask(() {
      _scheduledSave = null;
      if (isDisposed) return Future<void>.value();
      _hasFailedSave = false;
      if (store != null) {
        final (:activeRecords, :failedRecords, :removedIds, :releasedSequences) =
            _consumeTargetStoreState();
        final save = _pendingSaves.then((_) async {
          final changes = _diffAgainstPersisted(activeRecords, failedRecords, removedIds);
          try {
            if (changes.isNotEmpty) {
              await store!.apply(changes);
            }
            for (final change in changes) {
              switch (change) {
                case QueueRecordInsert(:final record):
                case QueueRecordUpdate(:final record):
                  _persistedRecords[record.id] = record;
                  if (record.state == QueueRecordState.failed) {
                    _durableIds.remove(record.id);
                  } else {
                    _durableIds.add(record.id);
                  }
                case QueueRecordRemove(:final id):
                  _persistedRecords.remove(id);
                  _durableIds.remove(id);
              }
            }
            for (final id in removedIds) {
              if (findEvent(id) == null) {
                if (_persistedRecords[id]?.state != QueueRecordState.failed) {
                  _persistedRecords.remove(id);
                }
                _durableIds.remove(id);
              }
            }
            for (final id in activeRecords.keys) {
              _durableIds.add(id);
            }
            resumeProcessing();
          } catch (_) {
            _hasFailedSave = true;
            _knownIds.addAll(removedIds);
            for (final MapEntry(:key, :value) in releasedSequences.entries) {
              _sequences.putIfAbsent(key, () => value);
            }
            for (final MapEntry(:key, :value) in failedRecords.entries) {
              _pendingFailedRecords.putIfAbsent(key, () => value);
            }
            rethrow;
          }
        });
        _pendingSaves = save.catchError((Object _) {});
        return save;
      }

      final currentIds = pendingEvents.map((event) => event.id).toSet();
      final removedSnapshotIds = <String>{
        for (final id in _knownIds)
          if (!currentIds.contains(id)) id,
      };
      _knownIds.removeAll(removedSnapshotIds);
      for (final id in removedSnapshotIds) {
        _sequences.remove(id);
        _preparedRecords.remove(id);
      }
      final currentQueueJson = _encodeCurrentQueue();
      final retryQueueJson = _encodeRetryQueue();
      final save = _pendingSaves.then((_) async {
        try {
          await saveCurrentQueue!(currentQueueJson);
          await saveRetryQueue!(retryQueueJson);
          _durableIds
            ..removeAll(removedSnapshotIds)
            ..addAll(currentIds);
          resumeProcessing();
        } catch (_) {
          _hasFailedSave = true;
          _knownIds.addAll(removedSnapshotIds);
          rethrow;
        }
      });
      // A failed save surfaces to the caller but must not block the saves after it.
      _pendingSaves = save.catchError((Object _) {});
      return save;
    });
  }

  String _encodeCurrentQueue() {
    return jsonEncode([
      ..._unhydratedCurrentQueueJson,
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
      ..._unhydratedRetryQueueJson,
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

int _compareRecords(QueueRecord a, QueueRecord b) {
  final bySequence = a.sequence.compareTo(b.sequence);
  return bySequence != 0 ? bySequence : a.id.compareTo(b.id);
}
