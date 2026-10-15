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

/// An event with a configurable [id] that fails its first [failures] runs with an [Exception]
/// and then completes with its [id].
class ScriptedEvent extends Event<String> {
  ScriptedEvent(this.id, {this.failures = 0, this.retryConfig});

  @override
  final String id;

  /// How many runs fail before the event succeeds.
  final int failures;

  @override
  RetryConfig? retryConfig;

  int runs = 0;

  @override
  Future<String> run() async {
    runs++;
    if (runs <= failures) throw Exception('$id failed on run $runs');
    return id;
  }

  @override
  String get type => 'ScriptedEvent';
}

/// A [LinearRetryConfig] that retries after [failingEventRetryDelay].
LinearRetryConfig shortRetryConfig({int maxRetries = 10}) =>
    LinearRetryConfig(maxRetries: maxRetries, delay: failingEventRetryDelay);

const failingEventRetryDelay = Duration(milliseconds: 50);

/// An event that takes [duration] to run.
class SlowEvent extends Event<void> {
  SlowEvent(this.duration);

  final Duration duration;

  @override
  String get id => 'slow';

  @override
  String get type => 'SlowEvent';

  @override
  RetryConfig? get retryConfig => null;

  @override
  Future<void> run() => Future.delayed(duration);
}
