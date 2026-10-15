## 1.1.0

 - **FEAT**: dependent events. `Queue.add` takes `dependsOn`, a list of pending events that must complete first. If a dependency is retried, its dependents move to the retry queue with it and are re-queued behind it in their original order. If a dependency fails permanently, its dependents fail with a `DependencyFailedException` without running. `HydratedQueue` persists dependencies.
 - **FEAT**: query pending events with `Queue.pendingEvents`, `Queue.findEvent` and `Queue.findEvents`.
 - **FIX**: `listenWhere` only passes errors for events of the listened type to `onError`, instead of throwing a `TypeError` for other events.
 - **FIX**: resuming a queue while an event is running no longer starts a second processing loop.
 - **FIX**: disposing a queue while an event is running no longer throws once the event completes.
 - **DOCS**: document every feature in the README.

## 1.0.0

> Note: This release has breaking changes.

 - **BREAKING** **CHORE**: require Dart SDK `^3.11.0`.
 - **BREAKING** **REFACTOR**: `Queue.waitFor` throws synchronously when the queue is already disposed.
 - **REFACTOR**: `HydratedQueue.hydrate` returns `Future<void>` instead of `FutureOr<void>`.
 - **REFACTOR**: reformat code with the Dart 3.11 formatter.
 - **TEST**: restructure tests with Given/When/Then.
 - **CHORE**: upgrade dependencies, raising the lower bounds of `meta` to `^1.17.0` and `uuid` to `^4.6.0`.

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
