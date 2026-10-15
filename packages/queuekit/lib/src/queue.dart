import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:queuekit/queuekit.dart';

/// The record emitted on [Queue.results] for every event that ran successfully.
typedef QueueListenerResult<T extends Event<U>, U extends Object?> = ({T event, U result});

/// The error callback of [Queue.listenAll] and [Queue.listenWhere].
typedef OnError<T extends Event<U>, U extends Object?> =
    FutureOr<void> Function(T event, EventFailedException error, StackTrace stackTrace);

/// Runs events one at a time, in the order they were added, while [startListenable] is started.
///
/// Failed events are retried according to their [Event.retryConfig], and events added with
/// `dependsOn` wait for their dependencies. Results and failures are published on [results].
base class Queue {
  Queue(this.startListenable) {
    startListenable.addListener(_updateRunning);
  }

  /// Starts and pauses this queue. Disposed together with the queue.
  final QueueStartListenable startListenable;

  final _currentQueue = <Event>[];
  final _retryQueue = <String, ({Event event, DateTime nextExecutionTime})>{};
  final _controller = StreamController<QueueListenerResult>.broadcast();

  /// The ids of the pending events each pending event depends on, keyed by the dependent's id.
  @protected
  final dependencies = <String, Set<String>>{};

  /// The timers that re-queue the events awaiting their own retry, keyed by event id.
  @protected
  final timers = <String, Timer>{};

  late bool _running = startListenable.isStarted;
  bool _processing = false;
  bool _disposed = false;

  /// The events waiting to run, in order. The first one is the event currently running.
  List<Event> get currentQueue => UnmodifiableListView(_currentQueue);

  /// The events waiting for a retry, keyed by event id, together with the events that are waiting
  /// for one of those events because they depend on it.
  Map<String, ({Event event, DateTime nextExecutionTime})> get retryQueue =>
      UnmodifiableMapView(_retryQueue);

  /// Every event that has not finished yet, in the order it will run: the [currentQueue]
  /// (including the event currently running) followed by the [retryQueue].
  Iterable<Event> get pendingEvents {
    _checkDisposed();
    return _currentQueue.followedBy(_retryQueue.values.map((entry) => entry.event));
  }

  /// The results of the events that ran successfully, as a broadcast stream.
  ///
  /// Failures are delivered as stream errors of type [EventFailedException]. See [listenAll],
  /// [listenWhere] and [waitFor] for typed ways to listen.
  Stream<QueueListenerResult> get results {
    _checkDisposed();
    return _controller.stream;
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
      addToRetryQueue(event.id, event, blockedUntil);
      return;
    }
    addToCurrentQueue(event);
    if (_running && _currentQueue.length == 1) {
      _start();
    }
  }

  /// Listens to the results of every event. Failures are delivered to [onError] with the event.
  StreamSubscription<QueueListenerResult<Event<Object?>, Object?>> listenAll(
    void Function(QueueListenerResult params)? onData, {
    OnError<Event<Object?>, Object?>? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return results.listen(
      onData,
      onError: (Object e, StackTrace s) {
        if (onError == null) return;
        _filterOnError<Event<Object?>, Object?>(e, s, onError);
      },
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  /// Listens to the results of the events of type [T], whose results are of type [U]. Failures of
  /// those events are delivered to [onError] with the event.
  StreamSubscription<QueueListenerResult<T, U>> listenWhere<T extends Event<U>, U extends Object?>(
    void Function(QueueListenerResult<T, U> params)? onData, {
    OnError<T, U>? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return results
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

  /// Completes with the result of [event] once it has run, or with its [EventFailedException]
  /// if it fails permanently.
  ///
  /// [event] has to be added to this queue, before or after calling [waitFor]; otherwise the
  /// returned future never completes. A failure that is going to be retried does not complete
  /// the future.
  Future<U> waitFor<T extends Event<U>, U extends Object?>(T event) {
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
        if (_scheduledRetry(error.event)) return;
        subscription.cancel();
        completer.completeError(error, stackTrace);
      },
    );
    return completer.future;
  }

  /// Cancels pending retries, closes [results], disposes [startListenable] and clears the queue.
  ///
  /// Using the queue afterwards throws a [StateError].
  void dispose() {
    _checkDisposed();
    startListenable.dispose();
    _controller.close();
    for (final timer in timers.values) {
      timer.cancel();
    }
    _currentQueue.clear();
    _retryQueue.clear();
    dependencies.clear();
    timers.clear();
    _running = false;
    _disposed = true;
  }

  /// Appends [event] to the [currentQueue] without starting the queue.
  @protected
  void addToCurrentQueue(Event event) {
    _checkDisposed();
    _currentQueue.add(event);
  }

  /// Removes the event at [index] from the [currentQueue].
  @protected
  void removeIndexFromCurrentQueue(int index) {
    _checkDisposed();
    _currentQueue.removeAt(index);
  }

  /// Puts [event] in the [retryQueue] under [id], due at [nextExecutionTime].
  @protected
  void addToRetryQueue(String id, Event event, DateTime nextExecutionTime) {
    _checkDisposed();
    _retryQueue[id] = (event: event, nextExecutionTime: nextExecutionTime);
  }

  /// Removes the event with [id] from the [retryQueue].
  @protected
  void removeFromRetryQueue(String id) {
    _checkDisposed();
    _retryQueue.remove(id);
  }

  /// Re-queues [event] after [duration], followed by the events that were waiting for it.
  @protected
  void addTimerForRetry(String id, Event event, Duration duration) {
    _checkDisposed();
    timers[id] = Timer(duration, () {
      removeFromRetryQueue(id);
      timers.remove(id);
      add(event);
      releaseUnblockedEvents();
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
          in _retryQueue.entries.toList()) {
        if (timers.containsKey(id) || _blockedUntil(event) != null) continue;
        removeFromRetryQueue(id);
        add(event);
        released = true;
      }
    } while (released);
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
    _running = shouldStartRunning;
    if (!_running) return;
    _start();
  }

  Future<void> _start() async {
    _checkDisposed();
    if (_processing) return;
    _processing = true;
    try {
      while (_running && _currentQueue.isNotEmpty) {
        final event = _currentQueue.first;
        final blockedUntil = _blockedUntil(event);
        if (blockedUntil != null) {
          removeIndexFromCurrentQueue(0);
          addToRetryQueue(event.id, event, blockedUntil);
          continue;
        }
        try {
          final result = await event.run();
          if (_disposed) return;
          dependencies.remove(event.id);
          _controller.add((event: event, result: result));
        } catch (e, s) {
          if (_disposed) return;
          final retryScheduled = _scheduleRetry(event);
          _controller.addError(EventFailedException(event: event, error: e, stackTrace: s));
          if (retryScheduled) {
            _parkDependents(event);
          } else {
            dependencies.remove(event.id);
            _failDependents(event, e, s);
          }
        }
        final index = _currentQueue.indexOf(event);
        if (index != -1) removeIndexFromCurrentQueue(index);
      }
    } finally {
      _processing = false;
    }
  }

  /// Schedules a retry for [event] and returns whether one was scheduled.
  bool _scheduleRetry(Event event) {
    final retryConfig = event.retryConfig;
    if (retryConfig == null || !retryConfig.canRetry) return false;
    retryConfig.retry();
    final duration = retryConfig.minimumDurationForCurrentRetry();
    addToRetryQueue(event.id, event, DateTime.now().toUtc().add(duration));
    addTimerForRetry(event.id, event, duration);
    return true;
  }

  /// Whether [event] is waiting for a retry of its own.
  bool _scheduledRetry(Event event) => timers.containsKey(event.id);

  /// The time until which [event] has to wait for a dependency in the [retryQueue], or `null`
  /// when none of its dependencies is waiting there.
  DateTime? _blockedUntil(Event event) {
    DateTime? blockedUntil;
    for (final id in dependencies[event.id] ?? const <String>{}) {
      final entry = _retryQueue[id];
      if (entry == null) continue;
      if (blockedUntil == null || entry.nextExecutionTime.isAfter(blockedUntil)) {
        blockedUntil = entry.nextExecutionTime;
      }
    }
    return blockedUntil;
  }

  /// Moves the events in the [currentQueue] that depend on [failed], directly or indirectly, to
  /// the [retryQueue] so that they run after it again.
  void _parkDependents(Event failed) {
    final until = _retryQueue[failed.id]!.nextExecutionTime;
    final parked = {failed.id};
    bool changed;
    do {
      changed = false;
      for (var i = 0; i < _currentQueue.length; i++) {
        final event = _currentQueue[i];
        if (parked.contains(event.id) || !_dependsOnAny(event, parked)) continue;
        parked.add(event.id);
        removeIndexFromCurrentQueue(i--);
        addToRetryQueue(event.id, event, until);
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
    final index = _currentQueue.indexOf(event);
    if (index != -1) removeIndexFromCurrentQueue(index);
    if (_retryQueue.containsKey(event.id)) {
      timers.remove(event.id)?.cancel();
      removeFromRetryQueue(event.id);
    }
  }
}
