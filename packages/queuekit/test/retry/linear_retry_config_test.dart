import 'package:queuekit/queuekit.dart';
import 'package:test/test.dart';

void main() {
  group('Given a LinearRetryConfig with a delay of 1 second', () {
    const delay = Duration(seconds: 1);
    const maxRetries = 10;
    late LinearRetryConfig config;

    setUp(() {
      config = LinearRetryConfig(delay: delay, maxRetries: maxRetries);
    });

    test('Then the minimum duration for the current retry is zero', () {
      expect(config.minimumDurationForCurrentRetry(), equals(Duration.zero));
    });

    test('When calculating the minimum duration for arbitrary retry counts then it increases '
        'linearly', () {
      expect(config.minimumDurationForRetry(0), equals(Duration.zero));
      expect(config.minimumDurationForRetry(1), equals(const Duration(seconds: 1)));
      expect(config.minimumDurationForRetry(2), equals(const Duration(seconds: 2)));
      expect(config.minimumDurationForRetry(3), equals(const Duration(seconds: 3)));
    });

    test('When retried then the minimum duration for the current retry increases linearly', () {
      config.retry();
      expect(config.minimumDurationForCurrentRetry(), equals(const Duration(seconds: 1)));
      config.retry();
      expect(config.minimumDurationForCurrentRetry(), equals(const Duration(seconds: 2)));
      config.retry();
      expect(config.minimumDurationForCurrentRetry(), equals(const Duration(seconds: 3)));
    });

    group('When serialized and deserialized', () {
      late LinearRetryConfig restored;

      setUp(() {
        restored = config.serializer.fromJson(config.serializer.toJson(config));
      });

      test('Then the delay is preserved', () {
        expect(restored.delay, equals(delay));
      });

      test('Then maxRetries is preserved', () {
        expect(restored.maxRetries, equals(maxRetries));
      });
    });
  });
}
