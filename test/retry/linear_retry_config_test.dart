import 'package:queuekit/queuekit.dart';
import 'package:test/test.dart';

void main() {
  group('LinearRetryConfig', () {
    test('initial duration should be 0', () {
      final c = LinearRetryConfig(
        initialDelay: const Duration(seconds: 1),
        maxRetries: 10,
      );

      expect(c.durationForCurrentRetry(), equals(Duration.zero));
    });

    test('durationForRetry should be able to calculate for any arbitrary retry count', () {
      final c = LinearRetryConfig(
        initialDelay: const Duration(seconds: 1),
        maxRetries: 10,
      );

      expect(c.durationForRetry(0), equals(Duration.zero));
      expect(c.durationForRetry(1), equals(const Duration(seconds: 1)));
      expect(c.durationForRetry(2), equals(const Duration(seconds: 2)));
      expect(c.durationForRetry(3), equals(const Duration(seconds: 3)));
    });

    test('durationForCurrentRetry should increase linearly', () {
      final c = LinearRetryConfig(
        initialDelay: const Duration(seconds: 1),
        maxRetries: 10,
      );

      expect(c.durationForCurrentRetry(), equals(Duration.zero));
      c.retry();
      expect(c.durationForCurrentRetry(), equals(const Duration(seconds: 1)));
      c.retry();
      expect(c.durationForCurrentRetry(), equals(const Duration(seconds: 2)));
      c.retry();
      expect(c.durationForCurrentRetry(), equals(const Duration(seconds: 3)));
    });
  });
}
