import 'package:queuekit/queuekit.dart';
import 'package:test/test.dart';

import 'utils/events.dart';

void main() {
  group('Given a paused Queue with pending events', () {
    late Queue queue;
    late ScriptedEvent a;
    late ScriptedEvent b;

    setUp(() {
      queue = Queue(QueueStartListenable());
      a = ScriptedEvent('a');
      b = ScriptedEvent('b');
      queue.add(a);
      queue.add(b);
    });

    tearDown(() => queue.dispose());

    test('Then pendingEvents lists them in the order they will run', () {
      expect(queue.pendingEvents, [same(a), same(b)]);
    });

    test('Then findEvent returns the pending event with the given id', () {
      expect(queue.findEvent('b'), same(b));
    });

    test('Then findEvent returns null for an id that is not pending', () {
      expect(queue.findEvent('missing'), isNull);
    });

    test('Then findEvents returns the pending events of the given type', () {
      expect(queue.findEvents<ScriptedEvent>(), [same(a), same(b)]);
      expect(queue.findEvents<EventA>(), isEmpty);
    });

    test('Then findEvents narrows the pending events down with where', () {
      expect(queue.findEvents<ScriptedEvent>(where: (event) => event.id == 'b'), [same(b)]);
    });
  });

  group('Given a started Queue with an event awaiting a retry', () {
    late Queue queue;
    late ScriptedEvent a;

    setUp(() async {
      queue = Queue(QueueStartListenable()..start());
      a = ScriptedEvent('a', failures: 1, retryConfig: shortRetryConfig());
      queue.add(a);
      await Future.delayed(processingTime);
    });

    tearDown(() => queue.dispose());

    test('Then pendingEvents still lists it', () {
      expect(queue.currentQueue, isEmpty);
      expect(queue.pendingEvents, [same(a)]);
    });

    test('Then findEvent still finds it', () {
      expect(queue.findEvent('a'), same(a));
    });
  });

  group('Given a started Queue with a listenAll listener', () {
    late Queue queue;
    late List<String> completedIds;
    late List<EventFailedException> errors;

    setUp(() {
      queue = Queue(QueueStartListenable()..start());
      completedIds = [];
      errors = [];
      queue.listenAll(
        (result) {
          completedIds.add(result.event.id);
        },
        onError: (event, error, stackTrace) {
          errors.add(error);
        },
      );
    });

    tearDown(() => queue.dispose());

    group('When an event that depends on an event that fails once is added behind it', () {
      late ScriptedEvent b;
      late ScriptedEvent c;
      late ScriptedEvent d;

      setUp(() {
        b = ScriptedEvent('b', failures: 1, retryConfig: shortRetryConfig());
        c = ScriptedEvent('c');
        d = ScriptedEvent('d');
        queue.add(b);
        queue.add(c, dependsOn: [b]);
        queue.add(d);
      });

      group('and the dependency has failed', () {
        setUp(() async {
          await Future.delayed(processingTime);
        });

        test('Then the dependent waits in the retry queue behind the dependency', () {
          expect(queue.currentQueue, isEmpty);
          expect(queue.retryQueue.keys, ['b', 'c']);
        });

        test('Then the dependent has not run', () {
          expect(c.runs, equals(0));
        });

        test('Then independent events still run', () {
          expect(completedIds, ['d']);
        });
      });

      group('and the dependency has been retried', () {
        setUp(() async {
          await Future.delayed(retryTime);
        });

        test('Then the dependency runs before the dependent', () {
          expect(completedIds, ['d', 'b', 'c']);
        });

        test('Then nothing is left pending', () {
          expect(queue.pendingEvents, isEmpty);
        });

        test('Then only the dependency failed', () {
          expect(errors.map((error) => error.event.id), ['b']);
        });
      });
    });

    group('When an event is added that depends on an event awaiting a retry', () {
      late ScriptedEvent b;
      late ScriptedEvent c;

      setUp(() async {
        b = ScriptedEvent('b', failures: 1, retryConfig: shortRetryConfig());
        queue.add(b);
        await Future.delayed(processingTime);
        c = ScriptedEvent('c');
        queue.add(c, dependsOn: [b]);
      });

      test('Then it waits in the retry queue behind the dependency instead of running', () {
        expect(queue.currentQueue, isEmpty);
        expect(queue.retryQueue.keys, ['b', 'c']);
      });

      test('Then it runs after the dependency once the dependency is retried', () async {
        await Future.delayed(retryTime);

        expect(completedIds, ['b', 'c']);
        expect(queue.pendingEvents, isEmpty);
      });
    });

    group('When a chain of dependent events is added behind an event that fails once', () {
      late ScriptedEvent b;
      late ScriptedEvent c;
      late ScriptedEvent d;

      setUp(() {
        b = ScriptedEvent('b', failures: 1, retryConfig: shortRetryConfig());
        c = ScriptedEvent('c');
        d = ScriptedEvent('d');
        queue.add(b);
        queue.add(c, dependsOn: [b]);
        queue.add(d, dependsOn: [c]);
      });

      test('Then the whole chain waits in the retry queue in order', () async {
        await Future.delayed(processingTime);

        expect(queue.retryQueue.keys, ['b', 'c', 'd']);
      });

      test('Then the whole chain runs in order once the dependency is retried', () async {
        await Future.delayed(retryTime);

        expect(completedIds, ['b', 'c', 'd']);
      });
    });

    group('When an event depends on an event that exhausts its retries', () {
      late ScriptedEvent b;
      late ScriptedEvent c;

      setUp(() async {
        b = ScriptedEvent('b', failures: 2, retryConfig: shortRetryConfig(maxRetries: 1));
        c = ScriptedEvent('c');
        queue.add(b);
        queue.add(c, dependsOn: [b]);
        await Future.delayed(retryTime);
      });

      test('Then the dependent fails with a DependencyFailedException without running', () {
        expect(c.runs, equals(0));
        expect(errors.map((error) => error.event.id), ['b', 'b', 'c']);
        expect(
          errors.last.error,
          isA<DependencyFailedException>().having((e) => e.dependency, 'dependency', same(b)),
        );
      });

      test('Then nothing is left pending', () {
        expect(queue.pendingEvents, isEmpty);
      });
    });

    group('When a chain of dependent events depends on an event without a retry config', () {
      late ScriptedEvent b;
      late ScriptedEvent c;
      late ScriptedEvent d;

      setUp(() async {
        b = ScriptedEvent('b', failures: 1);
        c = ScriptedEvent('c');
        d = ScriptedEvent('d');
        queue.add(b);
        queue.add(c, dependsOn: [b]);
        queue.add(d, dependsOn: [c]);
        await Future.delayed(processingTime);
      });

      test('Then every event in the chain fails in order without running', () {
        expect(errors.map((error) => error.event.id), ['b', 'c', 'd']);
        expect(c.runs, equals(0));
        expect(d.runs, equals(0));
      });

      test('Then each dependent names its direct dependency', () {
        expect(
          errors[1].error,
          isA<DependencyFailedException>().having((e) => e.dependency, 'dependency', same(b)),
        );
        expect(
          errors[2].error,
          isA<DependencyFailedException>()
              .having((e) => e.dependency, 'dependency', same(c))
              .having((e) => e.error, 'error', isA<DependencyFailedException>()),
        );
      });

      test('Then nothing is left pending', () {
        expect(queue.pendingEvents, isEmpty);
      });
    });

    test('When an event depends on an event that is not pending then it runs normally', () async {
      queue.add(ScriptedEvent('c'), dependsOn: [ScriptedEvent('b')]);
      await Future.delayed(processingTime);

      expect(completedIds, ['c']);
    });

    test('When waiting for an event whose dependency fails permanently then it fails with the '
        'DependencyFailedException', () async {
      final b = ScriptedEvent('b', failures: 1);
      final c = ScriptedEvent('c');
      queue.add(b);
      queue.add(c, dependsOn: [b]);

      await expectLater(
        queue.waitFor<ScriptedEvent, String>(c),
        throwsA(
          isA<EventFailedException>().having(
            (e) => e.error,
            'error',
            isA<DependencyFailedException>(),
          ),
        ),
      );
    });
  });
}

/// Long enough for a started queue to process its events.
const processingTime = Duration(milliseconds: 10);

/// Long enough for a failed event to be retried and processed.
final retryTime = failingEventRetryDelay + const Duration(milliseconds: 20);
