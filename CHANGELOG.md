# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](https://conventionalcommits.org) for commit guidelines.

## 1.1.0

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`queuekit` - `v1.1.0`](#queuekit---v110)

---

#### `queuekit` - `v1.1.0`

 - **FEAT**: dependent events. `Queue.add` takes `dependsOn`, a list of pending events that must complete first. If a dependency is retried, its dependents move to the retry queue with it and are re-queued behind it in their original order. If a dependency fails permanently, its dependents fail with a `DependencyFailedException` without running. `HydratedQueue` persists dependencies.
 - **FEAT**: query pending events with `Queue.pendingEvents`, `Queue.findEvent` and `Queue.findEvents`.
 - **FIX**: `listenWhere` only passes errors for events of the listened type to `onError`, instead of throwing a `TypeError` for other events.
 - **FIX**: resuming a queue while an event is running no longer starts a second processing loop.
 - **FIX**: disposing a queue while an event is running no longer throws once the event completes.
 - **DOCS**: add a repository README and document every feature in the package README.
 - **CHORE**: update the dpk configuration and agent skill for dpk 1.0.

## 1.0.0

### Changes

---

Packages with breaking changes:

 - [`queuekit` - `v1.0.0`](#queuekit---v100)

Packages with other changes:

 - There are no other changes in this release.

---

#### `queuekit` - `v1.0.0`

 - **BREAKING** **CHORE**: require Dart SDK `^3.11.0`.
 - **BREAKING** **REFACTOR**: `Queue.waitFor` throws synchronously when the queue is already disposed.
 - **REFACTOR**: `HydratedQueue.hydrate` returns `Future<void>` instead of `FutureOr<void>`.
 - **REFACTOR**: reformat code with the Dart 3.11 formatter.
 - **TEST**: restructure tests with Given/When/Then.
 - **CHORE**: upgrade dependencies, raising the lower bounds of `meta` to `^1.17.0` and `uuid` to `^4.6.0`.
 - **CHORE**: replace melos, fvm and script_runner with dpk and asdf.
 - **CHORE**: add the dpk agent skill.
 - **CHORE**: remove IDE settings from the repository.

## 2024-07-02

### Changes

---

Packages with breaking changes:

 - [`queuekit` - `v0.1.0`](#queuekit---v010)

Packages with other changes:

 - There are no other changes in this release.

---

#### `queuekit` - `v0.1.0`

 - **FEAT**: add check for if queue is already disposed.
 - **FEAT**: update readme.
 - **FEAT**: add license.
 - **FEAT**: update changelog.
 - **FEAT**: add waitFor.
 - **FEAT**: update example.
 - **FEAT**: fix queuekit.
 - **FEAT**: convert repo to monorepo using melos (#5).
 - **BREAKING** **FEAT**: remove HydratedEvent.

