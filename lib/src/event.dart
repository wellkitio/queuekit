import 'package:queuekit/queuekit.dart';

abstract class Event<T extends Object?> {
  String get type;

  RetryConfig? get retryConfig;

  Future<T> run();
}
