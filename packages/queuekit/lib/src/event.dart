import 'package:queuekit/queuekit.dart';

abstract class Event<T extends Object?> {
  String get id;

  String get type;

  RetryConfig? get retryConfig;

  Future<T> run();
}
