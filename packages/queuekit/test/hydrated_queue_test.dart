import 'dart:convert';

import 'package:queuekit/queuekit.dart';
import 'package:test/test.dart';

import 'utils/events.dart';

void main() {
  group('Given a HydratedQueue with persisted current and retry queues', () {
    late HydratedQueue queue;

    setUp(() {
      queue = HydratedQueue(
        QueueStartListenable(),
        eventSerializers: eventSerializers,
        hydrateCurrentQueue: () {
          return jsonEncode([
            {'type': 'EventA'},
            {'type': 'EventB'},
            {'type': 'FailingEventOnFirstTry'},
          ]);
        },
        hydrateRetryQueue: () {
          return jsonEncode({
            'id': {
              'type': 'EventA',
              'event': {},
              'nextExecutionTime': DateTime.now().add(const Duration(seconds: 1)).toIso8601String(),
            },
          });
        },
        saveCurrentQueue: (data) {},
        saveRetryQueue: (data) {},
      );
    });

    tearDown(() => queue.dispose());

    test('Then the current queue is empty', () {
      expect(queue.currentQueue, isEmpty);
    });

    group('When hydrated', () {
      setUp(() async {
        await queue.hydrate();
      });

      test('Then the persisted events are placed in the current queue', () {
        expect(queue.currentQueue, hasLength(3));
      });

      test('Then the persisted retries are placed in the retry queue', () {
        expect(queue.retryQueue, hasLength(1));
      });
    });
  });

  group('Given a started HydratedQueue with nothing persisted', () {
    late HydratedQueue queue;
    late List<List<Object?>> savedCurrentQueueTypes;
    late List<Map<String, dynamic>> savedRetryQueues;

    setUp(() {
      savedCurrentQueueTypes = [];
      savedRetryQueues = [];
      queue = HydratedQueue(
        QueueStartListenable()..start(),
        eventSerializers: eventSerializers,
        hydrateCurrentQueue: () {
          return '[]';
        },
        hydrateRetryQueue: () {
          return '{}';
        },
        saveCurrentQueue: (data) {
          final events = (jsonDecode(data) as List).cast<Map<String, dynamic>>();
          savedCurrentQueueTypes.add([for (final event in events) event['type']]);
        },
        saveRetryQueue: (data) {
          savedRetryQueues.add(jsonDecode(data) as Map<String, dynamic>);
        },
      );
    });

    tearDown(() => queue.dispose());

    test('Then the current queue is empty', () {
      expect(queue.currentQueue, isEmpty);
    });

    test('When events are added then they are placed in the current queue', () {
      queue.add(EventA());
      queue.add(EventB());
      queue.add(FailingEventOnFirstTry());

      expect(queue.currentQueue, hasLength(3));
    });

    group('When events are added and processed with one failing on its first try', () {
      setUp(() async {
        queue.add(EventA());
        queue.add(EventB());
        queue.add(FailingEventOnFirstTry());
        await Future.delayed(const Duration(milliseconds: 10));
      });

      test('Then the current queue is empty', () {
        expect(queue.currentQueue, isEmpty);
      });

      test('Then the failed event is placed in the retry queue', () {
        expect(queue.retryQueue, hasLength(1));
      });

      test('Then the current queue is saved after every change, with the three synchronous '
          'additions saved together', () {
        expect(savedCurrentQueueTypes, [
          ['EventA', 'EventB', 'FailingEventOnFirstTry'],
          ['EventB', 'FailingEventOnFirstTry'],
          ['FailingEventOnFirstTry'],
          <Object?>[],
        ]);
      });

      test('Then the retry queue is saved after every change', () {
        expect(savedRetryQueues.map((retryQueue) => retryQueue.length), [0, 0, 0, 1]);
      });
    });

    group('When events are added and the retry delay of the failed event has passed', () {
      setUp(() async {
        queue.add(EventA());
        queue.add(EventB());
        queue.add(FailingEventOnFirstTry());
        await Future.delayed(const Duration(milliseconds: 70));
      });

      test('Then the current queue is empty', () {
        expect(queue.currentQueue, isEmpty);
      });

      test('Then the retry queue is empty', () {
        expect(queue.retryQueue, isEmpty);
      });

      test('Then the last saved retry queue is empty', () {
        expect(savedRetryQueues.last, isEmpty);
      });
    });
  });
  group('Given a started HydratedQueue that records its saves', () {
    late HydratedQueue queue;
    late List<List<Map<String, dynamic>>> savedCurrentQueues;
    late List<Map<String, dynamic>> savedRetryQueues;

    setUp(() {
      savedCurrentQueues = [];
      savedRetryQueues = [];
      queue = HydratedQueue(
        QueueStartListenable()..start(),
        eventSerializers: eventSerializers,
        hydrateCurrentQueue: () => null,
        hydrateRetryQueue: () => null,
        saveCurrentQueue: (data) {
          savedCurrentQueues.add((jsonDecode(data) as List).cast<Map<String, dynamic>>());
        },
        saveRetryQueue: (data) {
          savedRetryQueues.add(jsonDecode(data) as Map<String, dynamic>);
        },
      );
    });

    tearDown(() => queue.dispose());

    group('When a dependent event is added behind an event that fails once', () {
      setUp(() async {
        final b = ScriptedEvent('b', failures: 1, retryConfig: shortRetryConfig());
        queue.add(b);
        queue.add(ScriptedEvent('c'), dependsOn: [b]);
        await Future.delayed(const Duration(milliseconds: 10));
      });

      test('Then the dependency is saved with the current queue', () {
        final saved = savedCurrentQueues.first;
        expect(saved.map((event) => event['id']), ['b', 'c']);
        expect(saved[0], isNot(contains('dependsOn')));
        expect(saved[1]['dependsOn'], ['b']);
      });

      test('Then the dependency is saved with the retry queue once both are waiting there', () {
        final saved = savedRetryQueues.last;
        expect(saved.keys, ['b', 'c']);
        expect(saved['b'], isNot(contains('dependsOn')));
        expect((saved['c'] as Map<String, dynamic>)['dependsOn'], ['b']);
      });

      test('Then only the dependency is saved as awaiting its own retry', () {
        final saved = savedRetryQueues.last;
        expect((saved['b'] as Map<String, dynamic>)['awaitingRetry'], isTrue);
        expect((saved['c'] as Map<String, dynamic>)['awaitingRetry'], isFalse);
      });
    });
  });

  group('Given a HydratedQueue with a persisted dependent event in the current queue', () {
    late HydratedQueue queue;

    setUp(() {
      queue = HydratedQueue(
        QueueStartListenable(),
        eventSerializers: eventSerializers,
        hydrateCurrentQueue: () {
          return jsonEncode([
            {'type': 'ScriptedEvent', 'name': 'b', 'failures': 1, 'retry': true},
            {
              'type': 'ScriptedEvent',
              'name': 'c',
              'dependsOn': ['b'],
            },
          ]);
        },
        hydrateRetryQueue: () => null,
        saveCurrentQueue: (data) {},
        saveRetryQueue: (data) {},
      );
    });

    tearDown(() => queue.dispose());

    group('When hydrated and started and the dependency fails', () {
      setUp(() async {
        await queue.hydrate();
        queue.startListenable.start();
        await Future.delayed(const Duration(milliseconds: 10));
      });

      test('Then the dependent waits in the retry queue behind the dependency', () {
        expect(queue.currentQueue, isEmpty);
        expect(queue.retryQueue.keys, ['b', 'c']);
      });
    });
  });

  group(
    'Given a HydratedQueue with a persisted retry queue holding a dependency and its dependent',
    () {
      late HydratedQueue queue;
      late DateTime nextExecutionTime;

      setUp(() {
        queue = HydratedQueue(
          QueueStartListenable(),
          eventSerializers: eventSerializers,
          hydrateCurrentQueue: () => null,
          hydrateRetryQueue: () {
            return jsonEncode({
              'b': {
                'type': 'ScriptedEvent',
                'event': {'name': 'b', 'retry': true},
                'nextExecutionTime': nextExecutionTime.toIso8601String(),
              },
              'c': {
                'type': 'ScriptedEvent',
                'event': {'name': 'c'},
                'nextExecutionTime': nextExecutionTime.toIso8601String(),
                'dependsOn': ['b'],
              },
            });
          },
          saveCurrentQueue: (data) {},
          saveRetryQueue: (data) {},
        );
      });

      tearDown(() => queue.dispose());

      group('When hydrated after the retry was due', () {
        setUp(() async {
          nextExecutionTime = DateTime.now().subtract(const Duration(seconds: 1));
          await queue.hydrate();
        });

        test('Then both are placed in the current queue in order', () {
          expect(queue.currentQueue.map((event) => event.id), ['b', 'c']);
          expect(queue.retryQueue, isEmpty);
        });
      });

      group('When hydrated before the retry is due', () {
        setUp(() async {
          nextExecutionTime = DateTime.now().add(const Duration(milliseconds: 50));
          await queue.hydrate();
        });

        test('Then both wait in the retry queue in order', () {
          expect(queue.currentQueue, isEmpty);
          expect(queue.retryQueue.keys, ['b', 'c']);
        });

        group('and the retry has become due', () {
          setUp(() async {
            await Future.delayed(const Duration(milliseconds: 100));
          });

          test('Then both are re-queued in order, once', () {
            expect(queue.currentQueue.map((event) => event.id), ['b', 'c']);
            expect(queue.retryQueue, isEmpty);
          });
        });
      });
    },
  );
}

final EventSerializers eventSerializers = {
  'EventA': (fromJson: (json) => EventA(), toJson: (event) => {}),
  'EventB': (fromJson: (json) => EventB(), toJson: (event) => {}),
  'FailingEventOnFirstTry': (fromJson: (json) => FailingEventOnFirstTry(), toJson: (event) => {}),
  'ScriptedEvent': (
    fromJson: (json) => ScriptedEvent(
      json['name'] as String,
      failures: json['failures'] as int? ?? 0,
      retryConfig: json['retry'] == true ? shortRetryConfig() : null,
    ),
    toJson: (event) {
      event as ScriptedEvent;
      return {
        'name': event.id,
        'failures': event.failures,
        if (event.retryConfig != null) 'retry': true,
      };
    },
  ),
};
