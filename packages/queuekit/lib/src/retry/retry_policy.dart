import 'package:meta/meta.dart';
import 'package:queuekit/queuekit.dart';

/// Decides what a [Queue] should do when [event] fails with [error] on attempt [attemptCount].
///
/// [attemptCount] starts at `1` for the first failed attempt and increases by `1` on each
/// subsequent failure, including failures that return [RetryDecision.pause]. Return `null` to fall
/// back to the event's [Event.retryConfig].
///
/// To count attempts differently, for example to not count a pause, override
/// [Queue.handleEventError].
typedef RetryPolicy = RetryDecision? Function(Event<Object?> event, Object error, int attemptCount);

/// The action a [Queue] takes after an [Event.run] attempt throws.
@immutable
sealed class RetryDecision {
  const RetryDecision();

  /// Schedules the event in the retry queue to run again at [nextAttemptAt].
  const factory RetryDecision.retryAt(DateTime nextAttemptAt) = RetryAtDecision;

  /// Fails the event permanently.
  ///
  /// In a store-backed [HydratedQueue], [retainRecord] controls whether the event's [QueueRecord]
  /// stays in the [QueueStore] with [QueueRecordState.failed] (`true`) or is removed (`false`).
  /// When omitted (`null`), the queue uses its [HydratedQueue.retainFailedEvents] setting.
  /// Dependent events also fail with [DependencyFailedException].
  const factory RetryDecision.fail({bool? retainRecord}) = FailDecision;

  /// Pauses the queue ([QueueStartListenable.pause]) and leaves the event at the front of the
  /// [Queue.currentQueue] so it runs again once the queue is resumed.
  ///
  /// By default the paused attempt counts as an attempt, like any other failure, and a
  /// [HydratedQueue] persists the new count. For a failure that was rejected rather than lost,
  /// such as a 401 while credentials are refreshed, override [Queue.handleEventError] to apply the
  /// pause without counting it.
  const factory RetryDecision.pause() = PauseDecision;
}

/// Schedules a failed event to run again at [nextAttemptAt].
@immutable
final class RetryAtDecision extends RetryDecision {
  const RetryAtDecision(this.nextAttemptAt);

  /// When the event becomes eligible to run again.
  final DateTime nextAttemptAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RetryAtDecision && nextAttemptAt.isAtSameMomentAs(other.nextAttemptAt));

  @override
  int get hashCode => nextAttemptAt.millisecondsSinceEpoch.hashCode;

  @override
  String toString() => 'RetryDecision.retryAt($nextAttemptAt)';
}

/// Fails an event permanently.
@immutable
final class FailDecision extends RetryDecision {
  const FailDecision({this.retainRecord});

  /// Whether a store-backed [HydratedQueue] keeps the event's [QueueRecord] in the [QueueStore]
  /// with [QueueRecordState.failed] instead of removing it, or `null` to use
  /// [HydratedQueue.retainFailedEvents].
  final bool? retainRecord;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is FailDecision && retainRecord == other.retainRecord);

  @override
  int get hashCode => retainRecord.hashCode;

  @override
  String toString() => 'RetryDecision.fail(retainRecord: $retainRecord)';
}

/// Pauses the queue and keeps the failed event at the front of the current queue.
@immutable
final class PauseDecision extends RetryDecision {
  const PauseDecision();

  @override
  bool operator ==(Object other) => other is PauseDecision;

  @override
  int get hashCode => (PauseDecision).hashCode;

  @override
  String toString() => 'RetryDecision.pause()';
}
