import 'package:queuekit/queuekit.dart';
import 'package:test/test.dart';

void main() {
  group(
    'Given an ExponentialBackoffRetryConfig with a delay of 1 second and a multiplier of 2',
    () {
      const delay = Duration(seconds: 1);
      const maxRetries = 10;
      const multiplier = 2.0;
      late ExponentialBackoffRetryConfig config;

      setUp(() {
        config = ExponentialBackoffRetryConfig(
          delay: delay,
          maxRetries: maxRetries,
          multiplier: multiplier,
        );
      });

      test('Then the minimum duration for the current retry is zero', () {
        expect(config.minimumDurationForCurrentRetry(), equals(Duration.zero));
      });

      test('When calculating the minimum duration for arbitrary retry counts then it increases '
          'exponentially', () {
        expect(config.minimumDurationForRetry(0), equals(Duration.zero));
        expect(config.minimumDurationForRetry(1), equals(const Duration(seconds: 2)));
        expect(config.minimumDurationForRetry(2), equals(const Duration(seconds: 4)));
        expect(config.minimumDurationForRetry(3), equals(const Duration(seconds: 8)));
      });

      test('When retried then the minimum duration for the current retry increases '
          'exponentially', () {
        config.retry();
        expect(config.minimumDurationForCurrentRetry(), equals(const Duration(seconds: 2)));
        config.retry();
        expect(config.minimumDurationForCurrentRetry(), equals(const Duration(seconds: 4)));
        config.retry();
        expect(config.minimumDurationForCurrentRetry(), equals(const Duration(seconds: 8)));
      });

      group('When serialized and deserialized', () {
        late ExponentialBackoffRetryConfig restored;

        setUp(() {
          restored = config.serializer.fromJson(config.serializer.toJson(config));
        });

        test('Then the delay is preserved', () {
          expect(restored.delay, equals(delay));
        });

        test('Then the multiplier is preserved', () {
          expect(restored.multiplier, equals(multiplier));
        });

        test('Then maxRetries is preserved', () {
          expect(restored.maxRetries, equals(maxRetries));
        });
      });
    },
  );
}
