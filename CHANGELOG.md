# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](https://conventionalcommits.org) for commit guidelines.

## 1.0.0 (unreleased)

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
 - **CHORE**: upgrade dependencies.
 - **CHORE**: reformat code with the Dart 3.11 formatter.
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

