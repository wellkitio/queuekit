import 'package:queuekit/queuekit.dart';
import 'package:test/test.dart';

final class TestRetryConfig extends RetryConfig {
  @override
  Duration durationForRetry(int retryCount) {
    throw UnimplementedError();
  }

  @override
  int get maxRetries => 1;
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
