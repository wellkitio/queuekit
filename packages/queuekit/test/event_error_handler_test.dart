import 'package:queuekit/queuekit.dart';
import 'package:test/test.dart';

import 'utils/events.dart';
import 'utils/queues.dart';

void main() {
  group('Given a started Queue subclass that records handleEventError calls', () {
    late RecordingErrorQueue queue;
    late List<EventFailedException> errors;

    setUp(() {
      queue = RecordingErrorQueue(QueueStartListenable()..start());
      errors = [];
      queue.listenAll((_) {}, onError: (event, error, stackTrace) => errors.add(error));
    });

    tearDown(() => queue.dispose());

    group('When an event without a retryConfig fails', () {
      late ScriptedEvent event;

      setUp(() async {
        event = ScriptedEvent('failing', failures: 1);
        queue.add(event);
        await Future<void>.delayed(processingTime);
      });

      test('Then handleEventError is called with the event, the error and the stack trace', () {
        final call = queue.calls.single;
        expect(call.event, same(event));
        expect(call.error, isA<Exception>().having((e) => '$e', 'message', contains('failing')));
        expect(call.stackTrace.toString(), isNotEmpty);
      });

      test('Then the default handling still fails the event permanently', () {
        expect(errors.single.event, same(event));
        expect(errors.single.willRetry, isFalse);
        expect(queue.pendingEvents, isEmpty);
      });
    });
  });

  group('Given a started Queue that pauses without counting, with a retryPolicy that returns '
      'scripted decisions', () {
    late FakeQueueClock clock;
    late QueueStartListenable startListenable;
    late PauseWithoutCountingQueue queue;
    late List<RetryDecision> decisions;
    late List<int> policyAttemptCounts;

    setUp(() {
      clock = FakeQueueClock(DateTime.utc(2026, 11, 3, 15));
      startListenable = QueueStartListenable()..start();
      decisions = [];
      policyAttemptCounts = [];
      queue = PauseWithoutCountingQueue(
        startListenable,
        clock: clock,
        retryPolicy: (event, error, attemptCount) {
          policyAttemptCounts.add(attemptCount);
          return decisions.removeAt(0);
        },
      );
      queue.listenAll((_) {}, onError: (event, error, stackTrace) {});
    });

    tearDown(() => queue.dispose());

    group('When an event fails and the policy pauses the queue', () {
      late ScriptedEvent event;

      setUp(() async {
        decisions = [const RetryDecision.pause()];
        event = ScriptedEvent('paused', failures: 1);
        queue.add(event);
        await Future<void>.delayed(processingTime);
      });

      test('Then the queue pauses with the event at the front of currentQueue', () {
        expect(startListenable.isStarted, isFalse);
        expect(queue.currentQueue, [same(event)]);
      });

      test('Then the policy receives attemptCount 1', () {
        expect(policyAttemptCounts, [1]);
      });

      test('Then the paused attempt is not counted', () {
        expect(queue.attemptCountOf(event), equals(0));
      });
    });

    group('When an event is paused twice', () {
      setUp(() async {
        decisions = [const RetryDecision.pause(), const RetryDecision.pause()];
        queue.add(ScriptedEvent('paused-twice', failures: 2));
        await Future<void>.delayed(processingTime);
        startListenable.start();
        await Future<void>.delayed(processingTime);
      });

      test('Then the policy receives attemptCount 1 both times', () {
        expect(policyAttemptCounts, [1, 1]);
      });
    });

    group('When an event is paused, resumed and then fails with a retryAt decision', () {
      late ScriptedEvent event;

      setUp(() async {
        decisions = [
          const RetryDecision.pause(),
          RetryDecision.retryAt(clock.now().add(const Duration(minutes: 1))),
        ];
        event = ScriptedEvent('paused-then-retried', failures: 3);
        queue.add(event);
        await Future<void>.delayed(processingTime);
        startListenable.start();
        await Future<void>.delayed(processingTime);
      });

      test('Then the retryAt failure is counted as attempt 1', () {
        expect(policyAttemptCounts, [1, 1]);
        expect(queue.attemptCountOf(event), equals(1));
        expect(queue.retryQueue, contains('paused-then-retried'));
      });

      group('and the retried event fails again', () {
        setUp(() async {
          decisions = [const RetryDecision.fail()];
          clock.advance(const Duration(minutes: 1));
          await Future<void>.delayed(processingTime);
        });

        test('Then the next failure is counted as attempt 2', () {
          expect(policyAttemptCounts, [1, 1, 2]);
        });
      });
    });
  });
}

/// A [Queue] that records every [handleEventError] call before deferring to the default.
final class RecordingErrorQueue extends Queue {
  RecordingErrorQueue(super.startListenable);

  final calls = <({Event event, Object error, StackTrace stackTrace})>[];

  @override
  void handleEventError(Event event, Object error, StackTrace stackTrace) {
    calls.add((event: event, error: error, stackTrace: stackTrace));
    super.handleEventError(event, error, stackTrace);
  }
}

/// A [Queue] whose paused attempts are not counted.
final class PauseWithoutCountingQueue extends Queue with PauseWithoutCounting {
  PauseWithoutCountingQueue(super.startListenable, {super.clock, super.retryPolicy});

  /// The attempts counted so far for [event], or `null` once it is no longer pending.
  int? attemptCountOf(Event event) => attemptCounts[event.id];
}
