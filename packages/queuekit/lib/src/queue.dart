import 'dart:async';

import 'package:meta/meta.dart';
import 'package:queuekit/queuekit.dart';
import 'package:uuid/uuid.dart';

typedef QueueListenerResult<T extends Event<U>, U extends Object?> = ({
  T event,
  U result,
});
typedef OnError<T extends Event<U>, U extends Object?> = FutureOr<void> Function(
  T event,
  EventFailedException error,
  StackTrace stackTrace,
);

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
  bool _disposed = false;
  @protected
  final timers = <String, Timer>{};

  void add(Event event) {
    _checkDisposed();
    currentQueue.add(event);
    if (running && currentQueue.length == 1) {
      _start();
    }
  }

  @protected
  void removeIndexFromCurrentQueue(int index) {
    _checkDisposed();
    currentQueue.removeAt(index);
  }

  @override
  StreamSubscription<QueueListenerResult> listen(
    void Function(QueueListenerResult params)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    _checkDisposed();
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  StreamSubscription<QueueListenerResult<T, U>> listenWhere<T extends Event<U>, U extends Object?>(
    void Function(QueueListenerResult<T, U> params)? onData, {
    OnError<T, U>? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    _checkDisposed();
    return _controller.stream.where((result) => result.event is T).cast<QueueListenerResult<T, U>>().listen(
      onData,
      onError: (Object e, StackTrace s) {
        if (onError == null) return;
        _filterOnError<T, U>(e, s, onError);
      },
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  StreamSubscription<QueueListenerResult<Event<Object?>, Object?>> listenAll(
    void Function(QueueListenerResult params)? onData, {
    OnError<Event<Object?>, Object?>? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    _checkDisposed();
    return _controller.stream.listen(
      onData,
      onError: (Object e, StackTrace s) {
        if (onError == null) return;
        _filterOnError<Event<Object?>, Object?>(e, s, onError);
      },
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  Future<U> waitFor<T extends Event<U>, U extends Object?>(T event) async {
    _checkDisposed();
    final completer = Completer<U>();
    late StreamSubscription<QueueListenerResult<T, U>> subscription;
    subscription = listenWhere<T, U>(
      (result) {
        if (event.id != result.event.id) return;
        subscription.cancel();
        completer.complete(result.result);
      },
      onError: (event_, error, stackTrace) {
        if (event_.id != event.id) return;
        subscription.cancel();
        completer.completeError(error, stackTrace);
      },
    );
    return completer.future;
  }

  void dispose() {
    _checkDisposed();
    startListenable.dispose();
    _controller.close();
    for (final MapEntry(value: timer) in timers.entries) {
      timer.cancel();
    }
    currentQueue.clear();
    retryQueue.clear();
    timers.clear();
    running = false;
    _disposed = true;
  }

  void _checkDisposed() {
    if (_disposed) throw StateError('Queue is already disposed');
  }

  void _filterOnError<T extends Event<U>, U extends Object?>(
    Object originalError,
    StackTrace originalStackTrace,
    OnError<T, U> onError,
  ) {
    if (originalError is! EventFailedException) return;
    onError(originalError.event as T, originalError, originalStackTrace);
  }

  void _updateRunning(bool shouldStartRunning) {
    _checkDisposed();
    running = shouldStartRunning;
    if (!running) return;
    _start();
  }

  Future<void> _start() async {
    _checkDisposed();
    for (int i = 0; i < currentQueue.length; i++) {
      if (!running) return;
      final event = currentQueue[i];
      try {
        final result = await event.run();
        _controller.add((event: event, result: result));
      } catch (e, s) {
        _controller.addError(EventFailedException(event: event, error: e, stackTrace: s));
        final retryConfig = event.retryConfig;
        if (retryConfig != null) {
          _addRetry(event, e, s);
        }
      }
      removeIndexFromCurrentQueue(i);
      i--;
    }
  }

  @protected
  void addToRetryQueue(String id, Event event, Duration duration) {
    _checkDisposed();
    final nextExecutionTime = DateTime.now().toUtc().add(duration);
    retryQueue.addAll({
      id: (
        event: event,
        nextExecutionTime: nextExecutionTime,
      ),
    });
  }

  @protected
  void removeFromRetryQueue(String id) {
    _checkDisposed();
    retryQueue.remove(id);
  }

  @protected
  void addTimerForRetry(String id, Event event, Duration duration) {
    _checkDisposed();
    timers.addAll({
      id: Timer(duration, () {
        removeFromRetryQueue(id);
        timers.remove(id);
        add(event);
      }),
    });
  }

  void _addRetry(Event event, Object e, StackTrace s) {
    _checkDisposed();
    final retryConfig = event.retryConfig;
    if (retryConfig == null || retryConfig.maxRetries == retryConfig.retryCount) {
      return;
    }
    retryConfig.retry();
    final duration = retryConfig.minimumDurationForCurrentRetry();
    addToRetryQueue(event.id, event, duration);
    addTimerForRetry(event.id, event, duration);
  }
}
