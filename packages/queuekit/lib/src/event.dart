import 'package:queuekit/queuekit.dart';

/// A unit of work that a [Queue] runs.
///
/// [T] is the type of the result that [run] produces.
abstract class Event<T extends Object?> {
  /// Identifies the event while it is pending.
  ///
  /// Must be unique among the pending events of a queue: the retry queue, dependencies and
  /// [Queue.findEvent] are keyed by it. Persist it with the event when using a [HydratedQueue].
  String get id;

  /// Names the kind of event. A [HydratedQueue] uses it to look up the event's serializer.
  String get type;

  /// How the queue retries the event when [run] throws, or `null` to never retry it.
  RetryConfig? get retryConfig;

  /// Does the work. Throwing fails the event.
  Future<T> run();
}
