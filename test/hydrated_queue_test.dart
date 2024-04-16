import 'package:queuekit/queuekit.dart';
import 'package:test/test.dart';

class EventA extends HydratedEvent<Object?, LinearRetryConfig> {
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
  String get type => 'EventA';

  @override
  late JsonSerializer<HydratedEvent<Object?, LinearRetryConfig>> serializer = JsonSerializer(
    fromJson: (json) {
      return EventA()
        ..retryConfig = linearRetryConfigSerializer.fromJson(json['retry'] as Map<String, dynamic>);
    },
    toJson: (config) {
      return {
        'retry': retryConfig?.serializer.toJson(retryConfig!),
      };
    },
  );
}

class EventB extends HydratedEvent<Object?, ExponentialBackoffRetryConfig> {
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
  String get type => 'EventB';

  @override
  late JsonSerializer<HydratedEvent<Object?, ExponentialBackoffRetryConfig>> serializer =
      JsonSerializer(
    fromJson: (json) {
      return EventB()
        ..retryConfig =
            exponentialBackoffRetryConfigSerializer.fromJson(json['retry'] as Map<String, dynamic>);
    },
    toJson: (config) {
      return {
        'retry': retryConfig?.serializer.toJson(retryConfig!),
      };
    },
  );
}

class FailingEventOnFirstTry extends HydratedEvent<Object?, LinearRetryConfig> {
  @override
  LinearRetryConfig? retryConfig = LinearRetryConfig(
    maxRetries: 10,
    delay: const Duration(milliseconds: 50),
  );

  @override
  Future<Object?> run() async {
    if (retryConfig!.retryCount == 0) {
      throw Exception('Failed on first try');
    } else {
      return null;
    }
  }

  @override
  String get type => 'FailingEventOnFirstTry';

  @override
  late JsonSerializer<HydratedEvent<Object?, LinearRetryConfig>> serializer = JsonSerializer(
    fromJson: (json) {
      return FailingEventOnFirstTry()
        ..retryConfig = linearRetryConfigSerializer.fromJson(json['retry'] as Map<String, dynamic>);
    },
    toJson: (config) {
      return {
        'retry': retryConfig?.serializer.toJson(retryConfig!),
      };
    },
  );
}

void main() {
  group('HydratedQueue', () {
    test('should hydrate events', () async {
      final qsl = QueueStartListenable();
      final queue = HydratedQueue(
        qsl,
        hydrateCurrentQueue: () {
          return [
            EventA(),
            EventB(),
            FailingEventOnFirstTry(),
          ];
        },
        hydrateRetryQueue: () {
          return {
            'id': (
              event: EventA(),
              nextExecutionTime: DateTime.now().add(const Duration(seconds: 1)),
            ),
          };
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
        hydrateCurrentQueue: () {
          return [];
        },
        hydrateRetryQueue: () {
          return {};
        },
        saveCurrentQueue: (json) async {
          switch (saveCurrentQueueCount) {
            case 0:
              expect(json.length, equals(1));
              expect(json.first['type'], equals('EventA'));
            case 1:
              expect(json.length, equals(2));
              expect(json[1]['type'], equals('EventB'));
            case 2:
              expect(json.length, equals(3));
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
        saveRetryQueue: (data) async {
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
