import 'package:state_notifier/state_notifier.dart';

class QueueStartListenable extends StateNotifier<bool> {
  QueueStartListenable() : super(false);

  bool get isStarted => state;

  void start() => state = true;

  void pause() => state = false;
}
