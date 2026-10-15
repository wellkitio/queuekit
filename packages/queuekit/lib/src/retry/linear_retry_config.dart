import 'package:queuekit/queuekit.dart';

final linearRetryConfigSerializer = JsonSerializer(
  fromJson: (json) {
    return LinearRetryConfig(
      maxRetries: json['maxRetries'] as int,
      delay: Duration(milliseconds: json['delay'] as int),
    )..retryCount = json['retryCount'] as int? ?? 0;
  },
  toJson: (config) {
    return {
      'maxRetries': config.maxRetries,
      'delay': config.delay.inMilliseconds,
      'retryCount': config.retryCount,
    };
  },
);

/// Retries after `delay × retryCount`: [delay], then twice [delay], and so on.
final class LinearRetryConfig extends RetryConfig {
  LinearRetryConfig({required super.maxRetries, required this.delay});

  final Duration delay;

  @override
  Duration minimumDurationForRetry(int retryCount) {
    return delay * retryCount;
  }

  @override
  JsonSerializer<LinearRetryConfig> get serializer => linearRetryConfigSerializer;
}
