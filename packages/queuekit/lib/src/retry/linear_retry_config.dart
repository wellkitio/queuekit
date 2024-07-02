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
    required super.maxRetries,
    required this.delay,
  });

  final Duration delay;

  @override
  Duration minimumDurationForRetry(int retryCount) {
    return delay * retryCount;
  }

  @override
  JsonSerializer<LinearRetryConfig> serializer = linearRetryConfigSerializer;
}
