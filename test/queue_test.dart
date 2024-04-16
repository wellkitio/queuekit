import 'package:queuekit/queuekit.dart';
import 'package:test/test.dart';

class EventA extends Event {
  @override
  RetryConfig? retryConfig = LinearRetryConfig(
    maxRetries: 10,
    delay: const Duration(seconds: 1),
  );

  @override
  Future<Object?> run() async {
    return null;
  }

  @override
  String get type => 'EventA';
}

class EventB extends Event {
  @override
  RetryConfig? retryConfig = ExponentialBackoffRetryConfig(
    maxRetries: 10,
    delay: const Duration(seconds: 1),
    multiplier: 2,
  );

  @override
  Future<Object?> run() async {
    return null;
  }

  @override
  String get type => 'EventB';
}

class FailingEventOnFirstTry extends Event {
  @override
  RetryConfig? retryConfig = LinearRetryConfig(
    maxRetries: 10,
    delay: const Duration(milliseconds: 50),
  );

  int count = 0;

  @override
  Future<Object?> run() async {
    count++;
    if (retryConfig!.retryCount == 0) {
      throw Exception('Failed on first try');
    } else {
      return null;
    }
  }

  @override
  String get type => 'FailingEventOnFirstTry';
}

void main() {
  group('Queue', () {
    test('Events should be executed', () async {
      final qsl = QueueStartListenable();
      qsl.start();
      final queue = Queue(qsl);
      final eventA = EventA();
      final eventB = EventB();

      expect(queue.currentQueue.length, equals(0));
      queue.add(eventA);
      expect(queue.currentQueue.length, equals(1));
      queue.add(eventB);
      expect(queue.currentQueue.length, equals(2));

      await Future.delayed(const Duration(milliseconds: 10));

      expect(queue.currentQueue.length, equals(0));
    });

    test('Events should be executed in order they are added', () async {
      final qsl = QueueStartListenable();
      qsl.start();
      final queue = Queue(qsl);
      final eventA = EventA();
      final eventB = EventB();

      int count = 0;
      queue.listenAll((params) {
        if (count == 0) {
          expect(params.event, isA<EventA>());
          count++;
        } else {
          expect(params.event, isA<EventB>());
        }
      });

      queue.add(eventA);
      queue.add(eventB);

      await Future.delayed(const Duration(milliseconds: 10));

      expect(queue.currentQueue.length, equals(0));
    });

    test('listenWhere should only emit the specified event type', () async {
      final qsl = QueueStartListenable();
      qsl.start();
      final queue = Queue(qsl);
      final eventA = EventA();
      final eventB = EventB();

      int count = 0;
      queue.listenWhere<EventA, LinearRetryConfig>((params) {
        if (count == 0) {
          expect(params.event, isA<EventA>());
          count++;
        } else {
          fail('${params.event.type} should not be emitted');
        }
      });

      queue.add(eventA);
      queue.add(eventB);

      await Future.delayed(const Duration(milliseconds: 10));

      expect(queue.currentQueue.length, equals(0));
    });

    test('Events should be retried based on the retry config', () async {
      final qsl = QueueStartListenable();
      qsl.start();
      final queue = Queue(qsl);
      final event = FailingEventOnFirstTry();

      int count = 0;
      queue.listenAll(
        (params) {
          if (count == 0) {
            fail('Event should not be successful on first try');
          } else {
            expect(params.event, isA<FailingEventOnFirstTry>());
            expect(params.result, isNull);
          }
        },
        onError: (event, error, stackTrace) {
          if (count == 0) {
            expect(event, isA<FailingEventOnFirstTry>());
            count++;
          } else {
            fail('Event should not fail on retry');
          }
        },
      );

      queue.add(event);

      await Future.delayed(const Duration(milliseconds: 1));

      expect(queue.currentQueue.length, equals(0));
      expect(queue.retryQueue.length, equals(1));

      await Future.delayed(const Duration(milliseconds: 60));

      expect(event.retryConfig?.retryCount, equals(1));
      expect(queue.currentQueue.length, equals(0));
      expect(queue.retryQueue.length, equals(0));
    });
  });
}
