import 'dart:math';

import 'package:queuekit/queuekit.dart';

final exponentialBackoffRetryConfigSerializer = JsonSerializer(
  fromJson: (json) {
    return ExponentialBackoffRetryConfig(
      maxRetries: json['maxRetries'] as int,
      delay: Duration(milliseconds: json['delay'] as int),
      multiplier: (json['multiplier'] as num).toDouble(),
    )..retryCount = json['retryCount'] as int? ?? 0;
  },
  toJson: (config) {
    return {
      'maxRetries': config.maxRetries,
      'delay': config.delay.inMilliseconds,
      'multiplier': config.multiplier,
      'retryCount': config.retryCount,
    };
  },
);

/// Retries after `delay × multiplier ^ retryCount`: with a [multiplier] of 2, [delay] × 2, then
/// [delay] × 4, and so on.
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
  JsonSerializer<ExponentialBackoffRetryConfig> get serializer =>
      exponentialBackoffRetryConfigSerializer;
}
