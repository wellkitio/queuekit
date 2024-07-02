import 'dart:math';

import 'package:queuekit/queuekit.dart';

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
    required super.maxRetries,
    required this.delay,
    required this.multiplier,
  });

  final Duration delay;
  final double multiplier;

  @override
  Duration minimumDurationForRetry(int retryCount) {
    if (retryCount == 0) return Duration.zero;
    return delay * pow(multiplier, retryCount);
  }

  @override
  JsonSerializer<ExponentialBackoffRetryConfig> serializer = exponentialBackoffRetryConfigSerializer;
}
