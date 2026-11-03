import 'dart:async';

/// Supplies the current time and schedules timers for a [Queue].
///
/// Defaults to the system wall clock ([QueueClock.system]). Inject a [FakeQueueClock] or a custom
/// [QueueClock] in tests to drive retry timing deterministically without waiting for real time.
class QueueClock {
  const QueueClock({
    DateTime Function() now = DateTime.now,
    Timer Function(Duration duration, void Function() callback) createTimer = Timer.new,
  }) : _now = now,
       _createTimer = createTimer;

  /// The system wall clock, backed by [DateTime.now] and [Timer.new].
  static const system = QueueClock();

  final DateTime Function() _now;
  final Timer Function(Duration duration, void Function() callback) _createTimer;

  /// The current time.
  DateTime now() => _now();

  /// Schedules [callback] to run after [duration].
  Timer createTimer(Duration duration, void Function() callback) =>
      _createTimer(duration, callback);
}

/// A controllable [QueueClock] for tests.
///
/// Time only moves when [advance] or [setNow] is called, and timers scheduled through
/// [createTimer] fire synchronously in due-time order as the clock reaches their deadline.
final class FakeQueueClock extends QueueClock {
  FakeQueueClock([DateTime? initialTime]) : _currentTime = initialTime ?? DateTime.utc(2026);

  DateTime _currentTime;
  int _nextId = 0;
  final _timers = <_FakeTimer>[];

  /// The number of active timers currently waiting to fire.
  int get pendingTimerCount => _timers.where((timer) => timer.isActive).length;

  @override
  DateTime now() => _currentTime;

  @override
  Timer createTimer(Duration duration, void Function() callback) {
    final effectiveDuration = duration.isNegative ? Duration.zero : duration;
    final timer = _FakeTimer(
      id: ++_nextId,
      dueAt: _currentTime.add(effectiveDuration),
      callback: callback,
      onCancel: _timers.remove,
    );
    _timers.add(timer);
    return timer;
  }

  /// Moves the clock forward by [duration] and fires every timer that becomes due, in order.
  ///
  /// Throws an [ArgumentError] if [duration] is negative.
  void advance(Duration duration) {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'must not be negative');
    }
    setNow(_currentTime.add(duration));
  }

  /// Sets the current time to [target] and fires every timer due at or before [target], in order.
  ///
  /// Throws an [ArgumentError] if [target] is earlier than [now].
  void setNow(DateTime target) {
    if (target.isBefore(_currentTime)) {
      throw ArgumentError.value(target, 'target', 'must not be before the current time');
    }
    while (true) {
      _FakeTimer? next;
      for (final timer in _timers) {
        if (!timer.isActive || timer.dueAt.isAfter(target)) continue;
        if (next == null ||
            timer.dueAt.isBefore(next.dueAt) ||
            (timer.dueAt.isAtSameMomentAs(next.dueAt) && timer.id < next.id)) {
          next = timer;
        }
      }
      if (next == null) break;
      _timers.remove(next);
      _currentTime = next.dueAt;
      next.fire();
    }
    _currentTime = target;
  }
}

final class _FakeTimer implements Timer {
  _FakeTimer({
    required this.id,
    required this.dueAt,
    required void Function() callback,
    required void Function(_FakeTimer timer) onCancel,
  }) : _callback = callback,
       _onCancel = onCancel;

  final int id;
  final DateTime dueAt;
  final void Function() _callback;
  final void Function(_FakeTimer timer) _onCancel;

  bool _active = true;
  int _tick = 0;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  @override
  void cancel() {
    _active = false;
    _onCancel(this);
  }

  void fire() {
    if (!_active) return;
    _active = false;
    _tick = 1;
    _callback();
  }
}
