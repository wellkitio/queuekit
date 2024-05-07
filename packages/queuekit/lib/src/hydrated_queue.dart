import 'dart:async';
import 'dart:convert';

import 'package:queuekit/queuekit.dart';

typedef EventSerializers = Map<
    String,
    ({
      HydratedEvent<Object?> Function(Map<String, dynamic> json) fromJson,
      Map<String, dynamic> Function(HydratedEvent<Object?> event) toJson,
    })>;

base class HydratedQueue extends Queue {
  HydratedQueue(
    super.startListenable, {
    required this.eventSerializers,
    required this.saveCurrentQueue,
    required this.saveRetryQueue,
    required this.hydrateCurrentQueue,
    required this.hydrateRetryQueue,
  });

  final EventSerializers eventSerializers;
  final FutureOr<void> Function(String data) saveCurrentQueue;
  final FutureOr<void> Function(String data) saveRetryQueue;
  final FutureOr<String?> Function() hydrateCurrentQueue;
  final FutureOr<String?> Function() hydrateRetryQueue;

  @override
  Future<void> add(covariant HydratedEvent event) async {
    super.add(event);
    await _save();
  }

  @override
  Future<void> removeIndexFromCurrentQueue(int index) async {
    super.removeIndexFromCurrentQueue(index);
    await _save();
  }

  @override
  Future<void> addToRetryQueue(String id, covariant HydratedEvent event, Duration duration) async {
    super.addToRetryQueue(id, event, duration);
    await _save();
  }

  FutureOr<void> hydrate() async {
    final rawCurrentQueue = await hydrateCurrentQueue();
    if (rawCurrentQueue != null) {
      final currentQueue = jsonDecode(rawCurrentQueue) as List;
      for (final event in currentQueue.cast<Map<String, dynamic>>()) {
        final serializer = eventSerializers[event['type']];
        if (serializer == null) continue;
        this.currentQueue.add(serializer.fromJson(event));
      }
    }

    final rawRetryQueue = await hydrateRetryQueue();
    if (rawRetryQueue == null) return;

    final retryQueue = jsonDecode(rawRetryQueue) as Map<String, dynamic>;
    for (final MapEntry(:key, :value) in retryQueue.cast<String, Map<String, dynamic>>().entries) {
      final serializer = eventSerializers[value['type']];
      if (serializer == null) continue;
      final event = serializer.fromJson(value['event'] as Map<String, dynamic>);
      final nextExecutionTime = DateTime.parse(value['nextExecutionTime'] as String);
      if (event.retryConfig!.retryCount >= event.retryConfig!.maxRetries) continue;
      final now = DateTime.now();
      if (nextExecutionTime.difference(now) <= Duration.zero) {
        currentQueue.add(event);
      } else {
        this.retryQueue[key] = (event: event, nextExecutionTime: nextExecutionTime);
        addTimerForRetry(key, event, nextExecutionTime.difference(now));
      }
    }
  }

  FutureOr<void> _save() async {
    final List<Map<String, dynamic>> currentQueueJson = [];
    for (final event in currentQueue) {
      final serializer = eventSerializers[event.type];
      if (serializer == null) continue;
      currentQueueJson.add({
        ...serializer.toJson(event as HydratedEvent),
        'type': event.type,
      });
    }
    final currentQueueString = jsonEncode(currentQueueJson);
    await saveCurrentQueue(currentQueueString);

    final Map<String, Map<String, dynamic>> retryQueueJson = {};
    for (final MapEntry(:key, :value) in retryQueue.entries) {
      final serializer = eventSerializers[value.event.type];
      if (serializer == null) continue;
      retryQueueJson[key] = {
        'type': value.event.type,
        'event': serializer.toJson(value.event as HydratedEvent),
        'nextExecutionTime': value.nextExecutionTime.toIso8601String(),
      };
    }
    final retryQueueString = jsonEncode(retryQueueJson);
    await saveRetryQueue(retryQueueString);
  }
}
