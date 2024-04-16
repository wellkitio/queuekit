import 'dart:async';

import 'package:queuekit/queuekit.dart';

typedef SaveFunction = FutureOr<void> Function(List<Map<String, dynamic>> json);
typedef HydrateFunction = FutureOr<List<HydratedEvent>> Function();
typedef SaveRetryFunction = FutureOr<void> Function(
  List<
          ({
            String id,
            Map<String, dynamic> event,
            DateTime nextExecutionTime,
          })>
      data,
);
typedef HydrateRetryFunction = FutureOr<
        Map<
            String,
            ({
              HydratedEvent event,
              DateTime nextExecutionTime,
            })>>
    Function();

base class HydratedQueue extends Queue {
  HydratedQueue(
    super.startListenable, {
    required this.saveCurrentQueue,
    required this.hydrateCurrentQueue,
    required this.saveRetryQueue,
    required this.hydrateRetryQueue,
  });

  final SaveFunction saveCurrentQueue;
  final HydrateFunction hydrateCurrentQueue;
  final SaveRetryFunction saveRetryQueue;
  final HydrateRetryFunction hydrateRetryQueue;

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
    final currentQueue = await hydrateCurrentQueue();
    final retryQueue = await hydrateRetryQueue();
    for (final event in currentQueue) {
      this.currentQueue.add(event);
    }
    for (final MapEntry(:key, :value) in retryQueue.entries) {
      if (value.event.retryConfig!.retryCount >= value.event.retryConfig!.maxRetries) continue;
      final now = DateTime.now();
      if (value.nextExecutionTime.difference(now) <= Duration.zero) {
        this.currentQueue.add(value.event);
      } else {
        this.retryQueue[key] = value;
        addTimerForRetry(key, value.event, value.nextExecutionTime.difference(now));
      }
    }
  }

  FutureOr<void> _save() async {
    await saveCurrentQueue(currentQueue.map((e) => e.toJson()).toList());
    await saveRetryQueue(
      retryQueue.entries.map((e) {
        return (
          id: e.key,
          event: e.value.event.toJson(),
          nextExecutionTime: e.value.nextExecutionTime,
        );
      }).toList(),
    );
  }
}
