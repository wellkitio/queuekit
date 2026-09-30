import 'package:queuekit/queuekit.dart';
import 'package:test/test.dart';

void main() {
  group('Given a RetryConfig with maxRetries of 1', () {
    late TestRetryConfig config;

    setUp(() {
      config = TestRetryConfig();
    });

    test('When retried then it returns normally', () {
      expect(() => config.retry(), returnsNormally);
    });
  });

  group('Given a RetryConfig that has reached maxRetries', () {
    late TestRetryConfig config;

    setUp(() {
      config = TestRetryConfig()..retry();
    });

    test('When retried then it throws a RetryExceededException', () {
      expect(() => config.retry(), throwsA(isA<RetryExceededException>()));
    });
  });
}

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
