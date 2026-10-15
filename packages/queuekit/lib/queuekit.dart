/// A persistent task queue for Dart and Flutter. Runs events in order, retries failures, keeps
/// dependent events in order and restores the queue across app restarts.
library;

export 'package:queuekit/src/event.dart';
export 'package:queuekit/src/exceptions.dart';
export 'package:queuekit/src/hydrated_queue.dart';
export 'package:queuekit/src/json_serializer.dart';
export 'package:queuekit/src/queue.dart';
export 'package:queuekit/src/queue_start_listenable.dart';
export 'package:queuekit/src/retry/exponential_backoff_retry_config.dart';
export 'package:queuekit/src/retry/linear_retry_config.dart';
export 'package:queuekit/src/retry/retry_config.dart';
