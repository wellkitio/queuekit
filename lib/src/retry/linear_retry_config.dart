import 'package:queuekit/src/retry/retry_config.dart';

final class LinearRetryConfig extends RetryConfig {
  LinearRetryConfig({
    required this.maxRetries,
    required this.delay,
  });

  @override
  final int maxRetries;
  final Duration delay;

  @override
  Duration minimumDurationForRetry(int retryCount) {
    return delay * retryCount;
  }
}
