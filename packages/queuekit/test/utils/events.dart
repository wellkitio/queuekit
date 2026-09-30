import 'package:queuekit/queuekit.dart';

class EventA extends Event<Object?> {
  @override
  LinearRetryConfig? retryConfig = LinearRetryConfig(
    maxRetries: 10,
    delay: const Duration(seconds: 1),
  );

  @override
  Future<Object?> run() async {
    return 'EventA';
  }

  @override
  String get type => 'EventA';

  @override
  String get id => 'eventAid';
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
  String get type => 'EventB';

  @override
  String get id => 'eventBid';
}

class FailingEventOnFirstTry extends Event<Object?> {
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
  String get id => 'id';
}
