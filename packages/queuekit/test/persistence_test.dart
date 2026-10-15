import 'dart:async';
import 'dart:convert';

import 'package:queuekit/queuekit.dart';
import 'package:test/test.dart';

import 'utils/events.dart';

void main() {
  group('Given a LinearRetryConfig that has been retried twice', () {
    late LinearRetryConfig config;

    setUp(() {
      config = LinearRetryConfig(maxRetries: 5, delay: const Duration(seconds: 1))
        ..retry()
        ..retry();
    });

    test('When serialized and deserialized then the retry count is preserved', () {
      final restored = config.serializer.fromJson(config.serializer.toJson(config));

      expect(restored.retryCount, equals(2));
    });

    test('When deserialized from JSON without a retry count then the retry count is zero', () {
      final restored = linearRetryConfigSerializer.fromJson({'maxRetries': 5, 'delay': 1000});

      expect(restored.retryCount, equals(0));
    });
  });

  group('Given an ExponentialBackoffRetryConfig that has been retried once', () {
    late ExponentialBackoffRetryConfig config;

    setUp(() {
      config = ExponentialBackoffRetryConfig(
        maxRetries: 5,
        delay: const Duration(seconds: 1),
        multiplier: 2,
      )..retry();
    });

    test('When serialized and deserialized then the retry count is preserved', () {
      final restored = config.serializer.fromJson(config.serializer.toJson(config));

      expect(restored.retryCount, equals(1));
    });

    test('When deserialized from JSON with an integer multiplier then it is accepted', () {
      final restored = exponentialBackoffRetryConfigSerializer.fromJson({
        'maxRetries': 5,
        'delay': 1000,
        'multiplier': 2,
      });

      expect(restored.multiplier, equals(2.0));
    });
  });

  group('Given a HydratedQueue with a persisted retry whose retries are almost used up', () {
    late HydratedQueue queue;
    late List<EventFailedException> errors;

    setUp(() {
      errors = [];
      queue = HydratedQueue(
        QueueStartListenable(),
        eventSerializers: countingSerializers,
        hydrateCurrentQueue: () => null,
        hydrateRetryQueue: () {
          return jsonEncode({
            'b': {
              'type': 'CountingEvent',
              'event': {
                'id': 'b',
                'retryConfig': {'maxRetries': 2, 'delay': 10, 'retryCount': 2},
              },
              'nextExecutionTime': DateTime.now()
                  .subtract(const Duration(seconds: 1))
                  .toIso8601String(),
            },
          });
        },
        saveCurrentQueue: (data) {},
        saveRetryQueue: (data) {},
      );
      queue.listenAll(
        (result) {},
        onError: (event, error, stackTrace) {
          errors.add(error);
        },
      );
    });

    tearDown(() => queue.dispose());

    group('When hydrated, started and the event fails again', () {
      setUp(() async {
        await queue.hydrate();
        queue.startListenable.start();
        await Future.delayed(const Duration(milliseconds: 20));
      });

      test('Then it is not retried any further', () {
        expect(errors, hasLength(1));
        expect(queue.pendingEvents, isEmpty);
      });
    });
  });

  group('Given a HydratedQueue with a persisted retry that retries forever', () {
    late HydratedQueue queue;

    setUp(() {
      queue = HydratedQueue(
        QueueStartListenable(),
        eventSerializers: countingSerializers,
        hydrateCurrentQueue: () => null,
        hydrateRetryQueue: () {
          return jsonEncode({
            'b': {
              'type': 'CountingEvent',
              'event': {
                'id': 'b',
                'retryConfig': {'maxRetries': -1, 'delay': 10, 'retryCount': 0},
              },
              'nextExecutionTime': DateTime.now()
                  .subtract(const Duration(seconds: 1))
                  .toIso8601String(),
            },
          });
        },
        saveCurrentQueue: (data) {},
        saveRetryQueue: (data) {},
      );
    });

    tearDown(() => queue.dispose());

    test('When hydrated then the event is restored', () async {
      await queue.hydrate();

      expect(queue.currentQueue.map((event) => event.id), ['b']);
    });
  });

  group('Given a started HydratedQueue whose storage is slow for the first save', () {
    late HydratedQueue queue;
    late List<String> savedCurrentQueues;
    late Completer<void> firstSave;

    setUp(() {
      savedCurrentQueues = [];
      firstSave = Completer<void>();
      queue = HydratedQueue(
        QueueStartListenable()..start(),
        eventSerializers: countingSerializers,
        hydrateCurrentQueue: () => null,
        hydrateRetryQueue: () => null,
        saveCurrentQueue: (data) async {
          if (savedCurrentQueues.isEmpty) await firstSave.future;
          savedCurrentQueues.add(data);
        },
        saveRetryQueue: (data) {},
      );
    });

    tearDown(() => queue.dispose());

    group('When an event is added and processed while the first save is still pending', () {
      setUp(() async {
        queue.add(CountingEvent('a'));
        await Future.delayed(const Duration(milliseconds: 10));
        firstSave.complete();
        await Future.delayed(const Duration(milliseconds: 10));
      });

      test('Then the saves are written in the order they happened', () {
        expect(savedCurrentQueues.map((data) => (jsonDecode(data) as List).length), [1, 0]);
      });
    });
  });
}

/// An event that always fails and whose retry config is persisted.
class CountingEvent extends Event<void> {
  CountingEvent(this.id, {this.retryConfig});

  @override
  final String id;

  @override
  LinearRetryConfig? retryConfig;

  @override
  String get type => 'CountingEvent';

  @override
  Future<void> run() => Future<void>.error(Exception('$id failed'));
}

final EventSerializers countingSerializers = {
  'CountingEvent': (
    fromJson: (json) => CountingEvent(
      json['id'] as String,
      retryConfig: json['retryConfig'] == null
          ? null
          : linearRetryConfigSerializer.fromJson(json['retryConfig'] as Map<String, dynamic>),
    ),
    toJson: (event) {
      event as CountingEvent;
      return {
        'id': event.id,
        if (event.retryConfig case final config?)
          'retryConfig': linearRetryConfigSerializer.toJson(config),
      };
    },
  ),
};
