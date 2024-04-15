import 'dart:async';

import 'package:queuekit/queuekit.dart';
import 'package:uuid/uuid.dart';

typedef QueueListenerResult<T> = ({Event<T> event, T result});
typedef OnError<T> = FutureOr<void> Function(Event<T> event, Object error, StackTrace stackTrace);

base class Queue extends Stream<QueueListenerResult> {
  Queue(this.startListenable) {
    startListenable.addListener(_updateRunning);
  }

  final QueueStartListenable startListenable;
  final currentQueue = <Event>[];
  final retryQueue = <String, ({Event event, DateTime nextExecutionTime})>{};
  final uuid = const Uuid();

  late bool running = startListenable.isStarted;

  final _controller = StreamController<QueueListenerResult>.broadcast();
  final _timers = <String, Timer>{};

  void add(Event event) {
    currentQueue.add(event);
    if (running && currentQueue.length == 1) {
      _start();
    }
  }

  void _filterOnError<T>(
    Object originalError,
    StackTrace originalStackTrace,
    OnError<T> onError,
  ) {
    if (originalError is! EventFailedException) return;
    onError(originalError.event as Event<T>, originalError, originalStackTrace);
  }

  @override
  StreamSubscription<QueueListenerResult> listen(
    void Function(QueueListenerResult params)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  StreamSubscription<QueueListenerResult<T>> listenWhere<T>(
    void Function(QueueListenerResult<T> params)? onData, {
    OnError<T>? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _controller.stream
        .where((event) => event.result is T)
        .cast<QueueListenerResult<T>>()
        .listen(
      onData,
      onError: (Object e, StackTrace s) {
        if (onError == null) return;
        _filterOnError<T>(e, s, onError);
      },
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  StreamSubscription<QueueListenerResult> listenAll(
    void Function(QueueListenerResult params)? onData, {
    OnError? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _controller.stream.listen(
      onData,
      onError: (Object e, StackTrace s) {
        if (onError == null) return;
        _filterOnError(e, s, onError);
      },
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  void dispose() {
    startListenable.dispose();
    _controller.close();
    for (final MapEntry(value: timer) in _timers.entries) {
      timer.cancel();
    }
  }

  void _updateRunning(bool shouldStartRunning) {
    running = shouldStartRunning;
    if (!running) return;
    _start();
  }

  Future<void> _start() async {
    for (int i = 0; i < currentQueue.length; i++) {
      if (!running) return;
      final event = currentQueue[i];
      try {
        final result = await event.run();
        _controller.add((event: event, result: result));
      } catch (e, s) {
        final retryConfig = event.retryConfig;
        if (retryConfig == null) {
          _controller.addError(EventFailedException(event: event, error: e, stackTrace: s));
          retryQueue.addAll({});
        }
      }

      currentQueue.removeRange(i, i + 1);
      i--;
      final retryConfig = event.retryConfig;
      if (retryConfig == null || retryConfig.maxRetries == retryConfig.retryCount) continue;
      retryConfig.retry();
      final nextExecutionTime = DateTime.now().toUtc().add(retryConfig.minimumDurationForCurrentRetry());
      final id = uuid.v4();
      retryQueue.addAll({
        id: (
          event: event,
          nextExecutionTime: nextExecutionTime,
        ),
      });
      _timers.addAll({
        id: Timer(retryConfig.minimumDurationForCurrentRetry(), () {
          currentQueue.add(event);
          retryQueue.remove(id);
          _timers.remove(id);
        }),
      });
    }
  }
}
