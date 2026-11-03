import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:queuekit/queuekit.dart';

/// The persisted lifecycle state of a [QueueRecord] in a [QueueStore].
enum QueueRecordState {
  /// In the [Queue.currentQueue], waiting to run (or currently running).
  pending,

  /// In the [Queue.retryQueue], waiting for [QueueRecord.nextAttemptAt] or for a dependency.
  scheduled,

  /// Permanently failed. Terminal: not restored into the active queue by [HydratedQueue.hydrate].
  failed,
}

/// A predicate that selects which persisted [QueueRecord]s to restore during
/// [HydratedQueue.hydrate].
typedef QueueRecordFilter = bool Function(QueueRecord record);

/// The persisted representation of a single [Event] in a [QueueStore].
@immutable
final class QueueRecord {
  QueueRecord({
    required this.id,
    required this.type,
    required Map<String, dynamic> eventJson,
    this.state = QueueRecordState.pending,
    Iterable<String> dependsOn = const [],
    this.attemptCount = 0,
    this.nextAttemptAt,
    this.awaitingRetry = false,
    this.sequence = 0,
    this.error,
  }) : eventJson = _freezeMap(eventJson),
       dependsOn = Set<String>.unmodifiable(dependsOn);

  /// Rebuilds a [QueueRecord] from the map produced by [toJson].
  factory QueueRecord.fromJson(Map<String, dynamic> json) {
    final nextAttemptAt = json['nextAttemptAt'] as String?;
    return QueueRecord(
      id: json['id'] as String,
      type: json['type'] as String,
      eventJson: Map<String, dynamic>.from(json['event'] as Map),
      state: QueueRecordState.values.byName(json['state'] as String? ?? 'pending'),
      dependsOn: (json['dependsOn'] as List?)?.cast<String>() ?? const [],
      attemptCount: json['attemptCount'] as int? ?? 0,
      nextAttemptAt: nextAttemptAt == null ? null : DateTime.parse(nextAttemptAt),
      awaitingRetry: json['awaitingRetry'] as bool? ?? false,
      sequence: json['sequence'] as int? ?? 0,
      error: json['error'] as String?,
    );
  }

  /// The [Event.id] of the persisted event.
  final String id;

  /// The [Event.type] used to look up the event's [EventSerializer].
  final String type;

  /// The serialized event payload produced by [EventSerializer.toJson].
  final Map<String, dynamic> eventJson;

  /// The persisted state of the event.
  final QueueRecordState state;

  /// The ids of the pending events that this event depends on.
  final Set<String> dependsOn;

  /// The number of failed attempts recorded for this event so far.
  final int attemptCount;

  /// When the next retry is due if [state] is [QueueRecordState.scheduled], or `null` otherwise.
  final DateTime? nextAttemptAt;

  /// Whether a [QueueRecordState.scheduled] record is awaiting its own retry timer rather than
  /// waiting only for a dependency in the retry queue.
  final bool awaitingRetry;

  /// Monotonic ordering key that preserves queue order across restarts.
  final int sequence;

  /// The terminal error description when [state] is [QueueRecordState.failed], or `null` otherwise.
  final String? error;

  /// Returns a copy of this record with the given fields replaced.
  QueueRecord copyWith({
    String? id,
    String? type,
    Map<String, dynamic>? eventJson,
    QueueRecordState? state,
    Iterable<String>? dependsOn,
    int? attemptCount,
    Object? nextAttemptAt = _sentinel,
    bool? awaitingRetry,
    int? sequence,
    Object? error = _sentinel,
  }) {
    return QueueRecord(
      id: id ?? this.id,
      type: type ?? this.type,
      eventJson: eventJson ?? this.eventJson,
      state: state ?? this.state,
      dependsOn: dependsOn ?? this.dependsOn,
      attemptCount: attemptCount ?? this.attemptCount,
      nextAttemptAt: identical(nextAttemptAt, _sentinel)
          ? this.nextAttemptAt
          : nextAttemptAt as DateTime?,
      awaitingRetry: awaitingRetry ?? this.awaitingRetry,
      sequence: sequence ?? this.sequence,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }

  /// Converts this record to a JSON-encodable map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'event': eventJson,
      'state': state.name,
      if (dependsOn.isNotEmpty) 'dependsOn': dependsOn.toList(),
      'attemptCount': attemptCount,
      if (nextAttemptAt != null) 'nextAttemptAt': nextAttemptAt!.toIso8601String(),
      if (awaitingRetry || state == QueueRecordState.scheduled) 'awaitingRetry': awaitingRetry,
      'sequence': sequence,
      if (error != null) 'error': error,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! QueueRecord) return false;
    final sameNextAttempt = switch ((nextAttemptAt, other.nextAttemptAt)) {
      (null, null) => true,
      (final a?, final b?) => a.isAtSameMomentAs(b),
      _ => false,
    };
    return id == other.id &&
        type == other.type &&
        state == other.state &&
        attemptCount == other.attemptCount &&
        sameNextAttempt &&
        awaitingRetry == other.awaitingRetry &&
        sequence == other.sequence &&
        error == other.error &&
        _setEquals(dependsOn, other.dependsOn) &&
        _jsonEquals(eventJson, other.eventJson);
  }

  @override
  int get hashCode => Object.hash(
    id,
    type,
    state,
    attemptCount,
    nextAttemptAt?.millisecondsSinceEpoch,
    awaitingRetry,
    sequence,
    error,
    Object.hashAllUnordered(dependsOn),
    _jsonHash(eventJson),
  );

  @override
  String toString() =>
      'QueueRecord(id: $id, type: $type, state: ${state.name}, attemptCount: $attemptCount, '
      'nextAttemptAt: $nextAttemptAt, sequence: $sequence)';
}

const Object _sentinel = Object();

/// A single per-record mutation applied to a [QueueStore] as part of an atomic change set.
@immutable
sealed class QueueChange {
  const QueueChange();
}

/// Inserts [record] into a [QueueStore].
@immutable
final class QueueRecordInsert extends QueueChange {
  const QueueRecordInsert(this.record);

  final QueueRecord record;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is QueueRecordInsert && record == other.record);

  @override
  int get hashCode => Object.hash(QueueRecordInsert, record);

  @override
  String toString() => 'QueueRecordInsert($record)';
}

/// Updates an existing [record] (keyed by [QueueRecord.id]) in a [QueueStore].
@immutable
final class QueueRecordUpdate extends QueueChange {
  const QueueRecordUpdate(this.record);

  final QueueRecord record;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is QueueRecordUpdate && record == other.record);

  @override
  int get hashCode => Object.hash(QueueRecordUpdate, record);

  @override
  String toString() => 'QueueRecordUpdate($record)';
}

/// Removes the record with [id] from a [QueueStore].
@immutable
final class QueueRecordRemove extends QueueChange {
  const QueueRecordRemove(this.id);

  final String id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is QueueRecordRemove && id == other.id);

  @override
  int get hashCode => Object.hash(QueueRecordRemove, id);

  @override
  String toString() => 'QueueRecordRemove($id)';
}

/// Per-event storage for a [HydratedQueue].
///
/// Implement [load], [insert], [update] and [remove], and override [apply] to run a batch of
/// [QueueChange]s inside a single database transaction so that multi-record state transitions are
/// atomic.
abstract base class QueueStore {
  const QueueStore();

  /// Loads persisted records, optionally narrowed by [filter].
  ///
  /// Records are restored by [HydratedQueue.hydrate] in ascending [QueueRecord.sequence] order.
  FutureOr<Iterable<QueueRecord>> load({QueueRecordFilter? filter});

  /// Inserts a new [record].
  // ignore: avoid_futureor_void
  FutureOr<void> insert(QueueRecord record);

  /// Updates an existing [record] with the same [QueueRecord.id].
  // ignore: avoid_futureor_void
  FutureOr<void> update(QueueRecord record);

  /// Removes the record with [id].
  // ignore: avoid_futureor_void
  FutureOr<void> remove(String id);

  /// The highest [QueueRecord.sequence] currently in the store across all records.
  ///
  /// Used by [HydratedQueue.hydrate] when a `filter` is supplied so new records added afterwards
  /// receive a [QueueRecord.sequence] higher than any record in other partitions. The default
  /// implementation scans [load] without a filter.
  FutureOr<int> maxSequence() async {
    var max = 0;
    for (final record in await load()) {
      if (record.sequence > max) max = record.sequence;
    }
    return max;
  }

  /// Applies [changes] as one atomic batch.
  ///
  /// The default implementation runs [insert], [update] and [remove] in order. Database-backed
  /// stores should override this to wrap `super.apply(changes)` in a database transaction.
  // ignore: avoid_futureor_void
  FutureOr<void> apply(List<QueueChange> changes) async {
    for (final change in changes) {
      switch (change) {
        case QueueRecordInsert(:final record):
          await insert(record);
        case QueueRecordUpdate(:final record):
          await update(record);
        case QueueRecordRemove(:final id):
          await remove(id);
      }
    }
  }
}

/// An in-memory [QueueStore] whose [apply] batches are atomic.
final class InMemoryQueueStore extends QueueStore {
  InMemoryQueueStore([Iterable<QueueRecord> initialRecords = const []]) {
    for (final record in initialRecords) {
      _records[record.id] = record;
    }
  }

  final _records = <String, QueueRecord>{};

  /// The currently stored records, keyed by [QueueRecord.id].
  Map<String, QueueRecord> get records => UnmodifiableMapView(_records);

  @override
  Iterable<QueueRecord> load({QueueRecordFilter? filter}) {
    final values = (filter == null ? _records.values : _records.values.where(filter)).toList()
      ..sort((a, b) {
        final bySequence = a.sequence.compareTo(b.sequence);
        return bySequence != 0 ? bySequence : a.id.compareTo(b.id);
      });
    return values;
  }

  @override
  int maxSequence() {
    var max = 0;
    for (final record in _records.values) {
      if (record.sequence > max) max = record.sequence;
    }
    return max;
  }

  @override
  void insert(QueueRecord record) {
    _records[record.id] = record;
  }

  @override
  void update(QueueRecord record) {
    _records[record.id] = record;
  }

  @override
  void remove(String id) {
    _records.remove(id);
  }

  @override
  void apply(List<QueueChange> changes) {
    final next = Map<String, QueueRecord>.of(_records);
    for (final change in changes) {
      switch (change) {
        case QueueRecordInsert(:final record):
        case QueueRecordUpdate(:final record):
          next[record.id] = record;
        case QueueRecordRemove(:final id):
          next.remove(id);
      }
    }
    _records
      ..clear()
      ..addAll(next);
  }
}

Map<String, dynamic> _freezeMap(Map<String, dynamic> map) {
  return Map<String, dynamic>.unmodifiable({
    for (final MapEntry(:key, :value) in map.entries) key: _freezeValue(value),
  });
}

Object? _freezeValue(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable({
      for (final MapEntry(:key, :value) in value.entries) key.toString(): _freezeValue(value),
    });
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_freezeValue));
  }
  return value;
}

bool _setEquals(Set<String> a, Set<String> b) {
  return a.length == b.length && a.containsAll(b);
}

bool _jsonEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final MapEntry(:key, :value) in a.entries) {
      if (!b.containsKey(key) || !_jsonEquals(value, b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

int _jsonHash(Object? value) {
  if (value is Map) {
    return Object.hashAllUnordered(
      value.entries.map((entry) => Object.hash(entry.key, _jsonHash(entry.value))),
    );
  }
  if (value is List) {
    return Object.hashAll(value.map(_jsonHash));
  }
  return value.hashCode;
}
