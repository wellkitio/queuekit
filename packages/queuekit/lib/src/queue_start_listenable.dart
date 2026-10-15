import 'package:state_notifier/state_notifier.dart';

/// Starts and pauses a queue.
///
/// A queue only processes events while its listenable is started. It starts paused.
class QueueStartListenable extends StateNotifier<bool> {
  QueueStartListenable() : super(false);

  /// Whether the queue is currently started.
  bool get isStarted => state;

  /// Starts processing. Pending events run right away.
  void start() => state = true;

  /// Stops processing after the event that is currently running. Events can still be added.
  void pause() => state = false;
}
