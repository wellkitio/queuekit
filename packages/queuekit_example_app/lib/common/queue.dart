import 'dart:async';
import 'dart:convert';

import 'package:queuekit/queuekit.dart';
import 'package:shared_preferences/shared_preferences.dart';

final queueStartListenable = QueueStartListenable();
late final HydratedQueue queue;
late final SharedPreferences _prefs;

Future<void> setupQueue() async {
  _prefs = await SharedPreferences.getInstance();
  queue = HydratedQueue(
    queueStartListenable,
    saveCurrentQueue: _saveCurrentQueue,
    saveRetryQueue: _saveRetryQueue,
    hydrateCurrentQueue: _hydrateCurrentQueue,
    hydrateRetryQueue: _hydrateRetryQueue,
  );
}

FutureOr<void> _saveCurrentQueue(List<Map<String, dynamic>> json) async {
  await _prefs.setString('currentQueue', jsonEncode(json));
}

FutureOr<void> _saveRetryQueue(
  List<({Map<String, dynamic> event, String id, DateTime nextExecutionTime})>
      data,
) async {
  final dataToSave = [
    for (final item in data)
      {
        'id': item.id,
        'event': item.event,
        'nextExecutionTime': item.nextExecutionTime.toIso8601String(),
      },
  ];
  await _prefs.setString('retryQueue', jsonEncode(dataToSave));
}

FutureOr<List<HydratedEvent<Object?, RetryConfig>>>
    _hydrateCurrentQueue() async {
  final data = <HydratedEvent<Object?, RetryConfig>>[];
  return data;
}

FutureOr<
    Map<
        String,
        ({
          HydratedEvent<Object?, RetryConfig> event,
          DateTime nextExecutionTime
        })>> _hydrateRetryQueue() {
  final data = <String,
      ({
    HydratedEvent<Object?, RetryConfig> event,
    DateTime nextExecutionTime
  })>{};
  return data;
}
