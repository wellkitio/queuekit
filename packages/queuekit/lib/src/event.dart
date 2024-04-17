import 'package:queuekit/queuekit.dart';

abstract class Event<T extends Object?, U extends RetryConfig> {
  String get type;

  U? get retryConfig;

  Future<T> run();

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      if (retryConfig != null)
        'retryConfig': (retryConfig!.serializer as JsonSerializer<U>).toJson(
          retryConfig!,
        ),
    };
  }
}

abstract class HydratedEvent<T extends Object?, U extends RetryConfig> extends Event<T, U> {
  HydratedEvent();

  JsonSerializer<HydratedEvent> get serializer;
}
