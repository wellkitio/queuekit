final class RetryExceededException implements Exception {
  RetryExceededException({required this.maxRetries}) : stackTrace = StackTrace.current;

  final int maxRetries;
  final StackTrace stackTrace;

  @override
  String toString() {
    return 'RetryExceededException: Retry count exceeded maximum retries of $maxRetries: \n$stackTrace';
  }
}
