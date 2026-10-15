import 'package:queuekit/queuekit.dart';
import 'package:test/test.dart';

import 'utils/events.dart';

void main() {
  group('Given a started Queue', () {
    late Queue queue;

    setUp(() {
      queue = startedQueue();
    });

    test('Then the current queue is empty', () {
      expect(queue.currentQueue, isEmpty);
    });

    test('When an event is added then it is placed in the current queue', () {
      queue.add(EventA());

      expect(queue.currentQueue, hasLength(1));
    });

    test('When two events are added then both are placed in the current queue', () {
      queue.add(EventA());
      queue.add(EventB());

      expect(queue.currentQueue, hasLength(2));
    });

    test('When two events are added and processed then the current queue is empty', () async {
      queue.add(EventA());
      queue.add(EventB());
      await Future.delayed(processingTime);

      expect(queue.currentQueue, isEmpty);
    });

    test(
      'When waiting for an added event then it completes with the result of that event',
      () async {
        final eventA = EventA();
        queue.add(eventA);
        queue.add(EventB());

        expect(await queue.waitFor<EventA, Object?>(eventA), equals('EventA'));
      },
    );
  });

  group('Given a started Queue with a results listener', () {
    late Queue queue;
    late List<Object> received;

    setUp(() {
      queue = startedQueue();
      received = [];
      queue.results.listen(received.add, onError: received.add);
    });

    test('When an event succeeds and another fails then both are delivered', () async {
      queue.add(EventA());
      queue.add(FailingEventOnFirstTry());
      await Future.delayed(processingTime);

      expect(received, [
        isA<QueueListenerResult>().having((r) => r.result, 'result', 'EventA'),
        isA<EventFailedException>(),
      ]);
    });
  });

  group('Given a started Queue', () {
    late Queue queue;

    setUp(() {
      queue = startedQueue();
    });

    test('Then its current queue cannot be modified from outside', () {
      expect(() => queue.currentQueue.add(EventA()), throwsUnsupportedError);
    });

    test('Then its retry queue cannot be modified from outside', () {
      expect(() => queue.retryQueue.remove('id'), throwsUnsupportedError);
    });

    test('When waiting for an event that fails once then it completes with the retried '
        'result', () async {
      final event = FailingEventOnFirstTry();
      queue.add(event);

      await expectLater(queue.waitFor<FailingEventOnFirstTry, Object?>(event), completion(isNull));
      expect(event.retryConfig?.retryCount, equals(1));
    });
  });

  group('Given a started Queue with a running event', () {
    late Queue queue;

    setUp(() {
      queue = startedQueue();
      queue.add(SlowEvent(const Duration(milliseconds: 10)));
    });

    test('When disposed then no error is thrown once the event completes', () async {
      queue.dispose();

      await expectLater(Future.delayed(const Duration(milliseconds: 20)), completes);
    });
  });

  group('Given a started Queue with a listenAll listener', () {
    late Queue queue;
    late List<QueueListenerResult> results;

    setUp(() {
      queue = startedQueue();
      results = [];
      queue.listenAll(results.add);
    });

    test('When two events are added and processed then they are emitted in the order they were '
        'added', () async {
      queue.add(EventA());
      queue.add(EventB());
      await Future.delayed(processingTime);

      expect(results.map((result) => result.event), [isA<EventA>(), isA<EventB>()]);
    });
  });

  group('Given a started Queue with a listenWhere listener for EventA', () {
    late Queue queue;
    late List<QueueListenerResult<EventA, Object?>> results;

    setUp(() {
      queue = startedQueue();
      results = [];
      queue.listenWhere<EventA, Object?>(results.add);
    });

    test('When events of different types are added and processed then only EventA is '
        'emitted', () async {
      queue.add(EventA());
      queue.add(EventB());
      await Future.delayed(processingTime);

      expect(results.map((result) => result.event), [isA<EventA>()]);
    });
  });

  group('Given a started Queue with an event that fails on its first try', () {
    late Queue queue;
    late FailingEventOnFirstTry event;
    late List<QueueListenerResult> results;
    late List<EventFailedException> errors;

    setUp(() {
      queue = startedQueue();
      event = FailingEventOnFirstTry();
      results = [];
      errors = [];
      queue.listenAll(
        results.add,
        onError: (event, error, stackTrace) {
          errors.add(error);
        },
      );
    });

    group('When the event is added and fails', () {
      setUp(() async {
        queue.add(event);
        await Future.delayed(const Duration(milliseconds: 1));
      });

      test('Then it is removed from the current queue', () {
        expect(queue.currentQueue, isEmpty);
      });

      test('Then it is placed in the retry queue', () {
        expect(queue.retryQueue, hasLength(1));
      });

      test('Then the failure is emitted as an error', () {
        expect(errors.map((error) => error.event), [isA<FailingEventOnFirstTry>()]);
      });

      test('Then no result is emitted', () {
        expect(results, isEmpty);
      });
    });

    group('When the event is added and its retry delay has passed', () {
      setUp(() async {
        queue.add(event);
        await Future.delayed(const Duration(milliseconds: 70));
      });

      test('Then the retry count is 1', () {
        expect(event.retryConfig?.retryCount, equals(1));
      });

      test('Then the current queue is empty', () {
        expect(queue.currentQueue, isEmpty);
      });

      test('Then the retry queue is empty', () {
        expect(queue.retryQueue, isEmpty);
      });

      test('Then the retried event is emitted with its result', () {
        expect(results.single.event, isA<FailingEventOnFirstTry>());
        expect(results.single.result, isNull);
      });

      test('Then the event does not fail again', () {
        expect(errors, hasLength(1));
      });
    });
  });
}

Queue startedQueue() => Queue(QueueStartListenable()..start());
