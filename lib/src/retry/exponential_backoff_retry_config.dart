import 'dart:math';

import 'package:queuekit/queuekit.dart';
import 'package:queuekit/src/retry/retry_config.dart';

final exponentialBackoffRetryConfigSerializer = JsonSerializer(
  fromJson: (json) {
    return ExponentialBackoffRetryConfig(
      maxRetries: json['maxRetries'] as int,
      delay: Duration(milliseconds: json['delay'] as int),
      multiplier: json['multiplier'] as double,
    );
  },
  toJson: (config) {
    return {
      'maxRetries': config.maxRetries,
      'delay': config.delay.inMilliseconds,
      'multiplier': config.multiplier,
    };
  },
);

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

  @override
  JsonSerializer<RetryConfig> serializer =
      exponentialBackoffRetryConfigSerializer;
}
