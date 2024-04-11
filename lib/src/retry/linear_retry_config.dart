import 'package:queuekit/src/retry/retry_config.dart';

final class LinearRetryConfig extends RetryConfig {
  LinearRetryConfig({
    required this.maxRetries,
    required this.initialDelay,
  });

  @override
  final int maxRetries;
  final Duration initialDelay;

  @override
  Duration durationForRetry(int retryCount) {
    return initialDelay * retryCount;
  }
}
