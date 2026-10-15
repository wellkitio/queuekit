import 'package:queuekit/queuekit.dart';

/// Decides when a failed event is retried.
///
/// Extend it and implement [minimumDurationForRetry]. Provide a [serializer] so a [HydratedQueue]
/// can persist the config with its event. See [LinearRetryConfig] and
/// [ExponentialBackoffRetryConfig] for the built-in strategies.
abstract base class RetryConfig {
  RetryConfig({required this.maxRetries});

  /// The number of retries after the first attempt. A negative value retries forever.
  int maxRetries;

  /// The number of retries that have been attempted so far, starting at 0.
  ///
  /// Serializers persist it, so a restored event continues where it left off.
  int retryCount = 0;

  /// The duration to wait before retry number [retryCount].
  ///
  /// Since the event is added to the back of the queue, it's not guaranteed that the event will
  /// be executed immediately after the duration has passed.
  Duration minimumDurationForRetry(int retryCount);

  /// The duration to wait before the next retry, based on the current [retryCount].
  Duration minimumDurationForCurrentRetry() => minimumDurationForRetry(retryCount);

  /// Whether a retry is still available.
  bool get canRetry => maxRetries < 0 || retryCount < maxRetries;

  /// Increments [retryCount], unless [maxRetries] is negative.
  ///
  /// Throws a [RetryExceededException] if no retries are left.
  void retry() {
    if (maxRetries < 0) return;
    if (retryCount >= maxRetries) {
      throw RetryExceededException(maxRetries: maxRetries);
    }
    retryCount++;
  }

  /// Converts this config to and from JSON, including [retryCount].
  JsonSerializer<RetryConfig> get serializer;
}
