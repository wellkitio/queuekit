import 'dart:async';

import 'package:meta/meta.dart';
import 'package:queuekit/queuekit.dart';
import 'package:uuid/uuid.dart';

typedef QueueListenerResult<T extends Event<U>, U extends Object?> = ({T event, U result});
typedef OnError<T extends Event<U>, U extends Object?> =
    FutureOr<void> Function(T event, EventFailedException error, StackTrace stackTrace);

base class Queue extends Stream<QueueListenerResult> {
  Queue(this.startListenable) {
    startListenable.addListener(_updateRunning);
  }

  final QueueStartListenable startListenable;

  /// The events waiting to run, in order. The first event is the one currently running.
  final currentQueue = <Event>[];

  /// The events waiting for a retry, keyed by event id, together with the events that are
  /// waiting for one of those events because they depend on it.
  final retryQueue = <String, ({Event event, DateTime nextExecutionTime})>{};
  final uuid = const Uuid();

  /// The ids of the pending events each pending event depends on, keyed by the dependent's id.
  @protected
  final dependencies = <String, Set<String>>{};

  late bool running = startListenable.isStarted;

  final _controller = StreamController<QueueListenerResult>.broadcast();
  bool _disposed = false;
  bool _processing = false;
  @protected
  final timers = <String, Timer>{};

  /// Every event that has not finished yet, in the order it will run: the [currentQueue]
  /// (including the event currently running) followed by the [retryQueue].
  Iterable<Event> get pendingEvents {
    _checkDisposed();
    return currentQueue.followedBy(retryQueue.values.map((entry) => entry.event));
  }

  /// The pending event with [id], or `null` when no pending event has that id.
  Event? findEvent(String id) {
    for (final event in pendingEvents) {
      if (event.id == id) return event;
    }
    return null;
  }

  /// The pending events of type [T], optionally narrowed down to those matching [where], in the
  /// order they will run.
  Iterable<T> findEvents<T extends Event>({bool Function(T event)? where}) {
    final events = pendingEvents.whereType<T>();
    return where == null ? events : events.where(where);
  }

  /// Adds [event] to the end of the queue.
  ///
  /// [dependsOn] lists pending events that must complete before [event] runs. While any of them
  /// is waiting in the [retryQueue], [event] waits there too, and it is re-queued right behind
  /// the dependency once the dependency is retried. If a dependency fails permanently, [event]
  /// fails with a [DependencyFailedException] without running. Events in [dependsOn] that are
  /// not pending are ignored.
  void add(Event event, {Iterable<Event> dependsOn = const []}) {
    _checkDisposed();
    final dependencyIds = {
      for (final dependency in dependsOn)
        if (dependency.id != event.id && findEvent(dependency.id) != null) dependency.id,
    };
    if (dependencyIds.isNotEmpty) {
      dependencies.update(
        event.id,
        (ids) => ids..addAll(dependencyIds),
        ifAbsent: () => dependencyIds,
      );
    }
    final blockedUntil = _blockedUntil(event);
    if (blockedUntil != null) {
      _park(event, blockedUntil);
      return;
    }
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
    return _controller.stream
        .where((result) => result.event is T)
        .cast<QueueListenerResult<T, U>>()
        .listen(
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

  Future<U> waitFor<T extends Event<U>, U extends Object?>(T event) {
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
    dependencies.clear();
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
    final event = originalError.event;
    if (event is! T) return;
    onError(event, originalError, originalStackTrace);
  }

  void _updateRunning(bool shouldStartRunning) {
    _checkDisposed();
    running = shouldStartRunning;
    if (!running) return;
    _start();
  }

  Future<void> _start() async {
    _checkDisposed();
    if (_processing) return;
    _processing = true;
    try {
      while (running && currentQueue.isNotEmpty) {
        final event = currentQueue.first;
        final blockedUntil = _blockedUntil(event);
        if (blockedUntil != null) {
          removeIndexFromCurrentQueue(0);
          _park(event, blockedUntil);
          continue;
        }
        try {
          final result = await event.run();
          if (_disposed) return;
          dependencies.remove(event.id);
          _controller.add((event: event, result: result));
        } catch (e, s) {
          if (_disposed) return;
          _controller.addError(EventFailedException(event: event, error: e, stackTrace: s));
          if (_scheduleRetry(event)) {
            _parkDependents(event);
          } else {
            dependencies.remove(event.id);
            _failDependents(event, e, s);
          }
        }
        final index = currentQueue.indexOf(event);
        if (index != -1) removeIndexFromCurrentQueue(index);
      }
    } finally {
      _processing = false;
    }
  }

  @protected
  void addToRetryQueue(String id, Event event, Duration duration) {
    _checkDisposed();
    final nextExecutionTime = DateTime.now().toUtc().add(duration);
    retryQueue.addAll({id: (event: event, nextExecutionTime: nextExecutionTime)});
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
        releaseUnblockedEvents();
      }),
    });
  }

  /// Moves every event that is waiting in the [retryQueue] only because of its dependencies, and
  /// whose dependencies are no longer waiting there, back to the [currentQueue].
  @protected
  void releaseUnblockedEvents() {
    _checkDisposed();
    bool released;
    do {
      released = false;
      for (final MapEntry(key: id, value: (:event, nextExecutionTime: _))
          in retryQueue.entries.toList()) {
        if (timers.containsKey(id) || _blockedUntil(event) != null) continue;
        removeFromRetryQueue(id);
        add(event);
        released = true;
      }
    } while (released);
  }

  /// Schedules a retry for [event] and returns whether one was scheduled.
  bool _scheduleRetry(Event event) {
    final retryConfig = event.retryConfig;
    if (retryConfig == null || retryConfig.maxRetries == retryConfig.retryCount) {
      return false;
    }
    retryConfig.retry();
    final duration = retryConfig.minimumDurationForCurrentRetry();
    addToRetryQueue(event.id, event, duration);
    addTimerForRetry(event.id, event, duration);
    return true;
  }

  /// The time until which [event] has to wait for a dependency in the [retryQueue], or `null`
  /// when none of its dependencies is waiting there.
  DateTime? _blockedUntil(Event event) {
    DateTime? blockedUntil;
    for (final id in dependencies[event.id] ?? const <String>{}) {
      final entry = retryQueue[id];
      if (entry == null) continue;
      if (blockedUntil == null || entry.nextExecutionTime.isAfter(blockedUntil)) {
        blockedUntil = entry.nextExecutionTime;
      }
    }
    return blockedUntil;
  }

  void _park(Event event, DateTime until) {
    addToRetryQueue(event.id, event, until.difference(DateTime.now().toUtc()));
  }

  /// Moves the events in the [currentQueue] that depend on [failed], directly or indirectly, to
  /// the [retryQueue] so that they run after it again.
  void _parkDependents(Event failed) {
    final until = retryQueue[failed.id]!.nextExecutionTime;
    final parked = {failed.id};
    bool changed;
    do {
      changed = false;
      for (var i = 0; i < currentQueue.length; i++) {
        final event = currentQueue[i];
        if (parked.contains(event.id) || !_dependsOnAny(event, parked)) continue;
        parked.add(event.id);
        removeIndexFromCurrentQueue(i--);
        _park(event, until);
        changed = true;
      }
    } while (changed);
  }

  /// Fails every pending event that depends on [failed], directly or indirectly, with a
  /// [DependencyFailedException].
  void _failDependents(Event failed, Object error, StackTrace stackTrace) {
    final failures = <String, ({Event event, Object error})>{
      failed.id: (event: failed, error: error),
    };
    bool changed;
    do {
      changed = false;
      for (final event in pendingEvents.toList()) {
        if (failures.containsKey(event.id) || !_dependsOnAny(event, failures.keys)) continue;
        final dependency = failures[dependencies[event.id]!.firstWhere(failures.containsKey)]!;
        final exception = DependencyFailedException(
          dependency: dependency.event,
          error: dependency.error,
        );
        failures[event.id] = (event: event, error: exception);
        _remove(event);
        dependencies.remove(event.id);
        _controller.addError(
          EventFailedException(event: event, error: exception, stackTrace: stackTrace),
        );
        changed = true;
      }
    } while (changed);
  }

  bool _dependsOnAny(Event event, Iterable<String> ids) {
    final eventDependencies = dependencies[event.id];
    return eventDependencies != null && ids.any(eventDependencies.contains);
  }

  void _remove(Event event) {
    final index = currentQueue.indexOf(event);
    if (index != -1) removeIndexFromCurrentQueue(index);
    if (retryQueue.containsKey(event.id)) {
      timers.remove(event.id)?.cancel();
      removeFromRetryQueue(event.id);
    }
  }
}
