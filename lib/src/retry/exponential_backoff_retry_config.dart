import 'dart:math';

import 'package:queuekit/src/retry/retry_config.dart';

final class ExponentialBackoffRetryConfig extends RetryConfig {
  ExponentialBackoffRetryConfig({
    required this.maxRetries,
    required this.delay,
    required this.multiplier,
  });

  @override
  final int maxRetries;
  final Duration delay;
  final double multiplier;

  @override
  Duration minimumDurationForRetry(int retryCount) {
    return delay * (retryCount == 0 ? 0 : pow(multiplier, retryCount));
  }
}
