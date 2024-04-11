import 'dart:math';

import 'package:queuekit/src/retry/retry_config.dart';

final class ExponentialBackoffRetryConfig extends RetryConfig {
  ExponentialBackoffRetryConfig({
    required this.maxRetries,
    required this.initialDelay,
    required this.multiplier,
  });

  @override
  final int maxRetries;
  final Duration initialDelay;
  final double multiplier;

  @override
  Duration durationForRetry(int retryCount) {
    return initialDelay * pow(multiplier, retryCount);
  }
}
