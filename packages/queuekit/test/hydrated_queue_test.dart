import 'dart:convert';

import 'package:queuekit/queuekit.dart';
import 'package:test/test.dart';

class EventA extends Event<Object?> {
  @override
  LinearRetryConfig? retryConfig = LinearRetryConfig(
    maxRetries: 10,
    delay: const Duration(seconds: 1),
  );

  @override
  Future<Object?> run() async {
    return null;
  }

  @override
  String get id => 'id';

  @override
  String get type => 'EventA';
}

class EventB extends Event<Object?> {
  @override
  ExponentialBackoffRetryConfig? retryConfig = ExponentialBackoffRetryConfig(
    maxRetries: 10,
    delay: const Duration(seconds: 1),
    multiplier: 2,
  );

  @override
  Future<Object?> run() async {
    return null;
  }

  @override
  String get id => 'id';

  @override
  String get type => 'EventB';
}

class FailingEventOnFirstTry extends Event<String?> {
  @override
  LinearRetryConfig? retryConfig = LinearRetryConfig(
    maxRetries: 10,
    delay: const Duration(milliseconds: 50),
  );

  @override
  Future<String?> run() async {
    if (retryConfig!.retryCount == 0) {
      throw Exception('Failed on first try');
    } else {
      return null;
    }
  }

  @override
  String get id => 'id';

  @override
  String get type => 'FailingEventOnFirstTry';
}

void main() {
  group('HydratedQueue', () {
    test('should hydrate events', () async {
      final qsl = QueueStartListenable();
      final queue = HydratedQueue(
        qsl,
        eventSerializers: {
          'EventA': (
            fromJson: (json) => EventA(),
            toJson: (event) => {},
          ),
          'EventB': (
            fromJson: (json) => EventB(),
            toJson: (event) => {},
          ),
          'FailingEventOnFirstTry': (
            fromJson: (json) => FailingEventOnFirstTry(),
            toJson: (event) => {},
          ),
        },
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
        saveCurrentQueue: (json) async {},
        saveRetryQueue: (data) async {},
      );

      expect(queue.currentQueue.length, equals(0));
      await queue.hydrate();
      expect(queue.currentQueue.length, equals(3));
      expect(queue.retryQueue.length, equals(1));
    });

    test('should save events', () async {
      final qsl = QueueStartListenable();
      qsl.start();
      int saveCurrentQueueCount = 0;
      int saveRetryQueueCount = 0;
      final queue = HydratedQueue(
        qsl,
        eventSerializers: {
          'EventA': (
            fromJson: (json) => EventA(),
            toJson: (event) => {},
          ),
          'EventB': (
            fromJson: (json) => EventB(),
            toJson: (event) => {},
          ),
          'FailingEventOnFirstTry': (
            fromJson: (json) => FailingEventOnFirstTry(),
            toJson: (event) => {},
          ),
        },
        hydrateCurrentQueue: () {
          return '[]';
        },
        hydrateRetryQueue: () {
          return '{}';
        },
        saveCurrentQueue: (jsonString) async {
          final json = jsonDecode(jsonString) as List;
          switch (saveCurrentQueueCount) {
            case 0:
              expect(json.length, equals(1));
              // ignore: avoid_dynamic_calls
              expect(json.first['type'], equals('EventA'));
            case 1:
              expect(json.length, equals(2));
              // ignore: avoid_dynamic_calls
              expect(json[1]['type'], equals('EventB'));
            case 2:
              expect(json.length, equals(3));
              // ignore: avoid_dynamic_calls
              expect(json[2]['type'], equals('FailingEventOnFirstTry'));
            case 3:
              expect(json.length, equals(2));
            case 4 || 5:
              expect(json.length, equals(1));
            case 6:
              expect(json.length, equals(0));
          }
          saveCurrentQueueCount++;
        },
        saveRetryQueue: (dataString) async {
          final data = jsonDecode(dataString) as Map;
          if (saveRetryQueueCount case 5 || 6) {
            expect(data.length, equals(1));
          } else {
            expect(data.length, equals(0));
          }
          saveRetryQueueCount++;
        },
      );

      expect(queue.currentQueue.length, equals(0));
      queue.add(EventA());
      queue.add(EventB());
      queue.add(FailingEventOnFirstTry());
      expect(queue.currentQueue.length, equals(3));
      await Future.delayed(const Duration(milliseconds: 10));
      expect(queue.currentQueue.length, equals(0));
      expect(queue.retryQueue.length, equals(1));
      await Future.delayed(const Duration(milliseconds: 60));
      expect(queue.currentQueue.length, equals(0));
      expect(queue.retryQueue.length, equals(0));
    });
  });
}
