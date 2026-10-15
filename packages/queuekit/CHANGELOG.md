## 1.0.0

> Note: This release has breaking changes.

> Not published separately: the first release after 0.1.0 includes it.

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
