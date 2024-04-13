import 'package:queuekit/queuekit.dart';
import 'package:test/test.dart';

void main() {
  group('ExponentialBackoffRetryConfig', () {
    test('initial duration should be 0', () {
      final c = ExponentialBackoffRetryConfig(
        initialDelay: const Duration(seconds: 1),
        maxRetries: 10,
        multiplier: 2,
      );

      expect(c.durationForCurrentRetry(), equals(Duration.zero));
    });

    test('durationForRetry should be able to calculate for any arbitrary retry count', () {
      final c = ExponentialBackoffRetryConfig(
        initialDelay: const Duration(seconds: 1),
        maxRetries: 10,
        multiplier: 2,
      );

      expect(c.durationForRetry(0), equals(Duration.zero));
      expect(c.durationForRetry(1), equals(const Duration(seconds: 2)));
      expect(c.durationForRetry(2), equals(const Duration(seconds: 4)));
      expect(c.durationForRetry(3), equals(const Duration(seconds: 8)));
    });

    test('durationForCurrentRetry should increase exponentially', () {
      final c = ExponentialBackoffRetryConfig(
        initialDelay: const Duration(seconds: 1),
        maxRetries: 10,
        multiplier: 2,
      );

      expect(c.durationForCurrentRetry(), equals(Duration.zero));
      c.retry();
      expect(c.durationForCurrentRetry(), equals(const Duration(seconds: 2)));
      c.retry();
      expect(c.durationForCurrentRetry(), equals(const Duration(seconds: 4)));
      c.retry();
      expect(c.durationForCurrentRetry(), equals(const Duration(seconds: 8)));
    });
  });
}
