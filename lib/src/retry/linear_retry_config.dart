import 'package:queuekit/queuekit.dart';

final linearRetryConfigSerializer = JsonSerializer(
  fromJson: (json) {
    return LinearRetryConfig(
      maxRetries: json['maxRetries'] as int,
      delay: Duration(milliseconds: json['delay'] as int),
    );
  },
  toJson: (config) {
    return {
      'maxRetries': config.maxRetries,
      'delay': config.delay.inMilliseconds,
    };
  },
);

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

  @override
  JsonSerializer<RetryConfig> serializer = linearRetryConfigSerializer;
}
