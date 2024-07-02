import 'package:queuekit/queuekit.dart';

/// [RetryConfig] is an abstract class that provides the configuration for retrying a task.
abstract base class RetryConfig {
  RetryConfig({required this.maxRetries});

  /// [maxRetries] is the maximum number of retries that will be attempted.
  /// If it's less than 0, it will retry indefinitely, and [retryCount] will never be incremented.
  int maxRetries;

  /// [retryCount] is the number of retries that have been attempted. It starts at 0.
  int retryCount = 0;

  /// [minimumDurationForRetry] is the duration to wait before the next retry.
  /// Since the event will be added to the back of the queue, it's not guaranteed that
  /// the event will be executed immediately after the duration has passed.
  Duration minimumDurationForRetry(int retryCount);

  /// [minimumDurationForCurrentRetry] is the duration to wait before the next retry based on the current [retryCount].
  /// Since the event will be added to the back of the queue, it's not guaranteed that
  /// the event will be executed immediately after the duration has passed.
  Duration minimumDurationForCurrentRetry() => minimumDurationForRetry(retryCount);

  /// [retry]  will increment [retryCount] if [maxRetries] is greater than 0 and it's not exceeded.
  /// If [maxRetries] is exceeded, it will throw a [RetryExceededException].
  void retry() {
    if (maxRetries < 0) return;
    if (retryCount >= maxRetries) {
      throw RetryExceededException(maxRetries: maxRetries);
    }
    retryCount++;
  }

  JsonSerializer<RetryConfig> get serializer;
}
