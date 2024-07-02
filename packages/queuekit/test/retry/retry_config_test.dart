import 'package:queuekit/queuekit.dart';
import 'package:test/test.dart';

final class TestRetryConfig extends RetryConfig {
  TestRetryConfig() : super(maxRetries: 1);

  @override
  Duration minimumDurationForRetry(int retryCount) {
    throw UnimplementedError();
  }

  @override
  JsonSerializer<TestRetryConfig> serializer = JsonSerializer(
    fromJson: (json) {
      throw UnimplementedError();
    },
    toJson: (config) {
      throw UnimplementedError();
    },
  );
}

void main() {
  group('RetryConfig', () {
    test('retry should throw a RetryExceededException if retied after reaching maxRetries', () {
      final c = TestRetryConfig();
      expect(() => c.retry(), returnsNormally);
      expect(() => c.retry(), throwsA(isA<RetryExceededException>()));
    });
  });
}
