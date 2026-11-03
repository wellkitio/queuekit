import 'package:queuekit/queuekit.dart';

/// Overrides [Queue.handleEventError] so that a [PauseDecision] does not count as an attempt, as
/// an app does when a 401 pauses the queue to refresh credentials.
base mixin PauseWithoutCounting on Queue {
  @override
  void handleEventError(Event event, Object error, StackTrace stackTrace) {
    final attemptCount = (attemptCounts[event.id] ?? event.retryConfig?.retryCount ?? 0) + 1;
    final decision = resolveRetryDecision(event, error, attemptCount);
    if (decision is! PauseDecision) attemptCounts[event.id] = attemptCount;
    applyRetryDecision(event, decision, error, stackTrace);
  }
}
