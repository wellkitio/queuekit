## 1.1.0

 - **FEAT**: dependent events. `Queue.add` takes `dependsOn`, a list of pending events that must complete first. If a dependency is retried, its dependents move to the retry queue with it and are re-queued behind it in their original order. If a dependency fails permanently, its dependents fail with a `DependencyFailedException` without running. `HydratedQueue` persists dependencies.
 - **FEAT**: query pending events with `Queue.pendingEvents`, `Queue.findEvent` and `Queue.findEvents`.
 - **FEAT**: `RetryConfig.canRetry`.
 - **FIX**: the built-in retry config serializers persist `retryCount`, so a restored event continues its retry budget and backoff instead of starting over after every restart.
 - **FIX**: `HydratedQueue.hydrate` no longer drops persisted retries whose config retries forever.
 - **FIX**: `HydratedQueue` writes saves one at a time, in order, so slow storage cannot persist an older state over a newer one.
 - **FIX**: `Queue.waitFor` no longer fails on a failure that is going to be retried; it completes with the eventual result or the final failure.
 - **FIX**: `exponentialBackoffRetryConfigSerializer` accepts an integer `multiplier`.
 - **FIX**: `listenWhere` only passes errors for events of the listened type to `onError`, instead of throwing a `TypeError` for other events.
 - **FIX**: resuming a queue while an event is running no longer starts a second processing loop.
 - **FIX**: disposing a queue while an event is running no longer throws once the event completes.
 - **DOCS**: document every feature in the README and the public API in dartdoc.

## 1.0.0

> Note: This release has breaking changes.

 - **BREAKING** **CHORE**: require Dart SDK `^3.11.0`.
 - **BREAKING** **REFACTOR**: `Queue.waitFor` throws synchronously when the queue is already disposed.
 - **BREAKING** **REFACTOR**: `Queue` no longer extends `Stream`. Listen through `Queue.results`, `listenAll`, `listenWhere` or `waitFor`.
 - **BREAKING** **REFACTOR**: `Queue.currentQueue` and `Queue.retryQueue` are read-only views, and `Queue.running` and `Queue.uuid` are removed.
 - **BREAKING** **REFACTOR**: the protected `Queue.addToRetryQueue` hook takes the absolute `nextExecutionTime`, and subclasses append restored events with the new protected `addToCurrentQueue`.
 - **REFACTOR**: `HydratedQueue.hydrate` returns `Future<void>` instead of `FutureOr<void>`.
 - **REFACTOR**: reformat code with the Dart 3.11 formatter.
 - **TEST**: restructure tests with Given/When/Then.
 - **CHORE**: upgrade dependencies, raising the lower bound of `meta` to `^1.17.0`, and drop the unused `uuid` dependency.

## 0.1.0

> Note: This release has breaking changes.

 - **FEAT**: add check for if queue is already disposed.
 - **FEAT**: update readme.
 - **FEAT**: add license.
 - **FEAT**: update changelog.
 - **FEAT**: add waitFor.
 - **FEAT**: update example.
 - **FEAT**: fix queuekit.
 - **FEAT**: convert repo to monorepo using melos (#5).
 - **BREAKING** **FEAT**: remove HydratedEvent.

## 0.0.1

- Initial version.
