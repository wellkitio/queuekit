import 'package:queuekit/queuekit.dart';

final class RetryExceededException implements Exception {
  RetryExceededException({required this.maxRetries})
      : stackTrace = StackTrace.current;

  final int maxRetries;
  final StackTrace stackTrace;

  @override
  String toString() {
    return 'RetryExceededException: Retry count exceeded maximum retries of $maxRetries: \n$stackTrace';
  }
}

final class EventFailedException<T> implements Exception {
  EventFailedException({
    required this.event,
    required this.error,
    required this.stackTrace,
  }) : super();

  final Event<T> event;
  final Object error;
  final StackTrace stackTrace;

  @override
  String toString() {
    return 'EventRunFailedException: Event run failed: \n$event\n$error\n$stackTrace';
  }
}
