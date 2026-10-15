## 1.1.0

 - **FEAT**: dependent events: `Queue.add` takes `dependsOn`, the pending events that must complete first.
   - If a dependency is retried, its dependents move to the retry queue with it and are re-queued behind it in their original order.
   - If a dependency fails permanently, its dependents fail with a `DependencyFailedException` without running.
   - `HydratedQueue` persists dependencies.
 - **FEAT**: query pending events with `Queue.pendingEvents`, `Queue.findEvent` and `Queue.findEvents`.
 - **FEAT**: `RetryConfig.canRetry`.
 - **FEAT**: `EventFailedException.willRetry` tells whether the failed event is going to be retried.
 - **FIX**: the built-in retry config serializers persist `retryCount`, so a restored event continues its retry budget and backoff instead of starting over after every restart.
 - **FIX**: `HydratedQueue.hydrate` no longer drops persisted retries whose config retries forever.
 - **FIX**: `HydratedQueue` writes saves one at a time, in order, so slow storage cannot persist an older state over a newer one.
 - **FIX**: `Queue.waitFor` no longer fails on a failure that is going to be retried; it completes with the eventual result or the final failure.
 - **FIX**: `exponentialBackoffRetryConfigSerializer` accepts an integer `multiplier`.
 - **FIX**: configs that retry forever (`maxRetries < 0`) no longer retry with no delay; `retryCount` now grows, so the built-in delays apply.
 - **FIX**: `HydratedQueue` saves the changes of one synchronous run together, so a retry that is re-queued is persisted in a single write instead of transiently disappearing from storage.
 - **FIX**: `HydratedQueue` records `awaitingRetry` on persisted retry entries, so a restored event waiting for its own retry keeps its timer and one waiting for a dependency does not get a spurious one.
 - **FIX**: a failed save no longer stops all later saves; the failure surfaces from the `add` future that caused it.
 - **FIX**: `HydratedQueue.hydrate` drops dependencies on events that could not be restored.
 - **FIX**: a finished event is removed from the dependencies of the events that depended on it, so reusing its id later cannot block them.
 - **FIX**: `listenWhere` only passes errors for events of the listened type to `onError`, instead of throwing a `TypeError` for other events.
 - **FIX**: resuming a queue while an event is running no longer starts a second processing loop.
 - **FIX**: disposing a queue while an event is running no longer throws once the event completes.
 - **DOCS**: document every feature in the README and the public API in dartdoc.

## 1.0.0

> Note: This release has breaking changes.

> Not published separately: shipped together with 1.1.0.

 - **BREAKING** **CHORE**: require Dart SDK `^3.11.0`.
 - **BREAKING** **REFACTOR**: `Queue.waitFor` throws synchronously when the queue is already disposed.
 - **BREAKING** **REFACTOR**: `Queue` no longer extends `Stream`. Listen through `Queue.results`, `listenAll`, `listenWhere` or `waitFor`.
 - **BREAKING** **REFACTOR**: `Queue.currentQueue` and `Queue.retryQueue` are read-only views, and `Queue.running` and `Queue.uuid` are removed.
 - **BREAKING** **REFACTOR**: the protected `Queue.removeIndexFromCurrentQueue(int)` hook is replaced by `removeFromCurrentQueue(Event)`; `addToRetryQueue` takes the absolute `nextExecutionTime`; subclasses get `addToCurrentQueue`, `releaseUnblockedEvents`, `isAwaitingRetry`, `isWaitingForDependency` and the `dependencies` map.
 - **BREAKING** **REFACTOR**: `LinearRetryConfig.serializer` and `ExponentialBackoffRetryConfig.serializer` are getters instead of mutable fields.
 - **BREAKING** **REFACTOR**: `EventFailedException.toString` names the event id and type.
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
