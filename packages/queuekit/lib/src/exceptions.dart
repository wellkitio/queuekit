import 'package:queuekit/queuekit.dart';

/// Thrown by [RetryConfig.retry] when it is called with no retries left.
final class RetryExceededException implements Exception {
  RetryExceededException({required this.maxRetries}) : stackTrace = StackTrace.current;

  final int maxRetries;
  final StackTrace stackTrace;

  @override
  String toString() {
    return 'RetryExceededException: Retry count exceeded maximum retries of $maxRetries: \n$stackTrace';
  }
}

/// Emitted on [Queue.results] when an event fails.
///
/// [error] and [stackTrace] are what [Event.run] threw, or a [DependencyFailedException] when the
/// event did not run because one of its dependencies failed permanently.
final class EventFailedException<T> implements Exception {
  EventFailedException({required this.event, required this.error, required this.stackTrace});

  final Event<T> event;
  final Object error;
  final StackTrace stackTrace;

  @override
  String toString() {
    return 'EventFailedException: Event ${event.id} (${event.type}) failed: \n$error\n$stackTrace';
  }
}

/// The error of an [EventFailedException] emitted for an event that could not run because an
/// event it depends on failed permanently.
///
/// [dependency] is the failed dependency and [error] is the error it failed with. When the
/// dependency itself failed because of one of its own dependencies, [error] is that dependency's
/// [DependencyFailedException].
final class DependencyFailedException implements Exception {
  DependencyFailedException({required this.dependency, required this.error});

  final Event<Object?> dependency;
  final Object error;

  @override
  String toString() {
    return 'DependencyFailedException: Dependency ${dependency.id} (${dependency.type}) failed: '
        '\n$error';
  }
}
