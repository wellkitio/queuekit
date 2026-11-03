import 'package:meta/meta.dart';
import 'package:state_notifier/state_notifier.dart';

/// Starts and pauses a queue.
///
/// A queue only processes events while its listenable is started. It starts paused.
class QueueStartListenable extends StateNotifier<bool> {
  QueueStartListenable() : super(false);

  final _onStartListeners = <void Function()>[];

  /// Whether the queue is currently started.
  bool get isStarted => state;

  /// Starts processing. Pending events run right away.
  void start() {
    if (state) {
      for (final listener in List<void Function()>.of(_onStartListeners)) {
        listener();
      }
      return;
    }
    state = true;
  }

  /// Stops processing after the event that is currently running. Events can still be added.
  void pause() => state = false;

  /// Registers a callback invoked when [start] is called while already started.
  @internal
  void addOnStartListener(void Function() listener) {
    _onStartListeners.add(listener);
  }

  @override
  void dispose() {
    _onStartListeners.clear();
    super.dispose();
  }
}
