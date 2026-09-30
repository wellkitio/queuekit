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

      test('Then the current queue is saved after every change', () {
        expect(savedCurrentQueueTypes, [
          ['EventA'],
          ['EventA', 'EventB'],
          ['EventA', 'EventB', 'FailingEventOnFirstTry'],
          ['EventB', 'FailingEventOnFirstTry'],
          ['FailingEventOnFirstTry'],
          ['FailingEventOnFirstTry'],
          <Object?>[],
        ]);
      });

      test('Then the retry queue is saved after every change', () {
        expect(savedRetryQueues.map((retryQueue) => retryQueue.length), [0, 0, 0, 0, 0, 1, 1]);
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
}

final EventSerializers eventSerializers = {
  'EventA': (fromJson: (json) => EventA(), toJson: (event) => {}),
  'EventB': (fromJson: (json) => EventB(), toJson: (event) => {}),
  'FailingEventOnFirstTry': (fromJson: (json) => FailingEventOnFirstTry(), toJson: (event) => {}),
};
