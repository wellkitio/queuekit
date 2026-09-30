---
name: dpk
description: Use dpk as an end-user CLI for Dart pub workflows, scripts, hooks, project caches, catalogs, patches, and dpk-specific command behavior.
---

# dpk Skill

Use this skill when helping someone use the `dpk` CLI in a Dart package or
workspace. The guidance is for end users and agents operating the CLI, not for
modifying dpk internals.

Run this guide from the CLI with:

```bash
dpk skills
```

`dpk skills` is configless. It works even when the current directory has no
`dpk.yaml` or `pubspec.yaml`.

## What dpk Does

`dpk` wraps common `dart pub` workflows and adds project conventions:

1. `dpk.yaml` configuration with a required `version` constraint.
2. Optional project-local package cache mode.
3. Configured scripts through `dpk run`.
4. Workspace-aware script execution.
5. Catalog-driven `pubspec.yaml` edits during `dpk get`.
6. Command hooks through `before`, `after`, `pre:<command>`, and
   `post:<command>` scripts.
7. Patch workflows for packages in a project-local cache.

## Basic Setup

Create a `dpk.yaml` beside the package `pubspec.yaml`:

```yaml
version: ^0.8.0
```

Use project cache mode when dependencies should be stored in a local
`pub_packages` directory:

```yaml
version: ^0.8.0
mode: project
```

Useful global options:

```bash
dpk -C packages/app get
dpk --directory packages/app run test
dpk --cache-dir .pub-cache get
dpk --verbose get
dpk --debug run build
```

Check the installed CLI version:

```bash
dpk --version
```

Initialize dpk configuration:

```bash
dpk init
dpk init --mode project
dpk init --version-constraint '^0.8.0'
dpk init --force
```

`dpk init` writes `dpk.yaml` only when `pubspec.yaml` exists in the target
directory. Use `--force` to overwrite an existing config file.

For configured commands, dpk starts from the current directory or `-C` target
and searches upward for `dpk.yaml`. In a Dart workspace, discovery stops at the
workspace root.

## Command Map

Dedicated dpk commands:

- `dpk init` creates `dpk.yaml`.
- `dpk skills` prints this guide.
- `dpk get` runs dpk-aware dependency resolution, catalog updates, sorting, and
  cache setup.
- `dpk run <script>` runs a script from `dpk.yaml`.
- `dpk patch init`, `dpk patch generate`, and `dpk patch apply` manage package
  patches.

Pub passthrough commands:

- `dpk add`
- `dpk bump`
- `dpk cache`
- `dpk deps`
- `dpk downgrade`
- `dpk global`
- `dpk login`
- `dpk logout`
- `dpk outdated`
- `dpk publish`
- `dpk remove`
- `dpk token`
- `dpk unpack`
- `dpk upgrade`
- `dpk update`, an alias for `dpk upgrade`
- `dpk workspace`

These passthrough commands run the matching `dart pub <command>` flow. They
also support dpk config discovery, project cache environment setup, dpk global
options, and hooks.

`dpk get` remains a dedicated dpk command because it performs extra dpk work
before and after dependency resolution.

## Dependency Commands

Add dependencies:

```bash
dpk add lints
dpk add --dev test
```

Fetch dependencies:

```bash
dpk get
dpk get --dry-run
dpk get --offline
dpk get --enforce-lockfile
dpk get --precompile
dpk get --color
dpk get --no-color
```

Upgrade, downgrade, inspect, or remove dependencies:

```bash
dpk upgrade
dpk update
dpk downgrade
dpk outdated
dpk deps
dpk remove lints
```

Run from another directory:

```bash
dpk -C packages/my_package get
dpk -C packages/my_package add collection
```

## Scripts

Define scripts in `dpk.yaml`:

```yaml
version: ^0.8.0
scripts:
  analyze: dart analyze
  test: dart test
  build:
    command: dart run build_runner build -d
```

Run scripts:

```bash
dpk run analyze
dpk run test
dpk run build
```

Pass arguments to scripts after the script name:

```bash
dpk run test --coverage
```

Use object-form scripts when a script needs environment variables, workspace
package execution, or inherited hooks:

```yaml
version: ^0.8.0
scripts:
  test:
    command: dart test
    description: Run unit tests
    env:
      CI: "true"
  test_all:
    command: dart test
    runInPackages:
      - packages/*
```

When `runInPackages` is used, dpk runs the command in each matching workspace
package and sets `DPK_ROOT` to the workspace root.

Object-form script fields are:

- `command`: shell command to run.
- `description`: optional help text for documenting the script.
- `env`: environment variables for the command.
- `runInPackages`: workspace package globs to run in.
- `runHooksFrom`: script or command name whose hooks should be used.
- `scripts`: hook target list for `before` and `after` hooks.
- `all`: when `true` on `before` or `after`, match every hookable command.

## Calling dpk Scripts From Other dpk Scripts

To run one dpk script from another dpk script, write the normal CLI command in
the script body:

```yaml
version: ^0.8.0
scripts:
  clean: dart run build_runner clean
  build:
    command: |
      dpk run clean
      dart run build_runner build -d
  publish:
    command: |
      dpk run build
      dpk publish
```

Use `dpk run <script>` explicitly. Do not call the script by bare name.

## Hooks

Scripts named `pre:<command>` and `post:<command>` run around matching dpk
commands:

```yaml
version: ^0.8.0
scripts:
  pre:get: echo "Before get"
  post:get: echo "After get"
```

Use `before` and `after` for shared hooks. They can target selected scripts:

```yaml
version: ^0.8.0
scripts:
  before:
    scripts:
      - test
      - build
    command: echo "Before selected scripts"
  after:
    scripts:
      - test
      - build
    command: echo "After selected scripts"
  test: dart test
  build: dart run build_runner build -d
```

Or target every hookable command with `all: true`:

```yaml
version: ^0.8.0
scripts:
  before:
    all: true
    command: echo "Before everything"
  after:
    all: true
    command: echo "After everything"
```

Hook order for most hookable commands is:

1. `before`
2. `pre:<command>`
3. the requested command
4. `post:<command>`
5. `after`

`dpk get` is special because scripts such as builds often require packages to
be fetched first. For `get`, matching `before` hooks are promoted into the
post-get phase:

1. `pre:get`
2. `dart pub get`
3. `before`
4. `post:get`
5. `after`

Hook scripts do not recursively hook `before`, `after`, `pre:*`, or `post:*`
themselves. If a `before` or `after` hook runs a script that would trigger the
same hook again, dpk skips the recursive hook and reports that it avoided an
infinite hook loop. This allows patterns such as running a build before other
scripts:

```yaml
version: ^0.8.0
scripts:
  before:
    scripts:
      - analyze
      - get
      - publish
      - watch
    command: dpk run build
  build: dart run build_runner build -d
  analyze: dart analyze
```

Use `runHooksFrom` when one script should run with another script's hook set.
The script still runs its own command, but dpk resolves `before`, `after`,
`pre:<name>`, and `post:<name>` hooks using the referenced script name:

```yaml
version: ^0.8.0
scripts:
  before:
    scripts:
      - build
    command: dpk run clean
  pre:build: echo "Preparing build"
  build: dart run build_runner build -d
  watch:
    runHooksFrom: build
    command: dart run build_runner watch -d
```

In this example, `dpk run watch` runs hooks as if the command name were
`build`, then runs the `watch` command.

## Workspace Scripts

Define workspace package globs in `dpk.yaml` when the root package should
manage multiple packages:

```yaml
version: ^0.8.0
workspace:
  - packages/*
```

dpk expands these globs to directories containing `pubspec.yaml` and writes the
expanded list to the root `pubspec.yaml` workspace field.

Use `runInPackages` to run a script across matching workspace packages:

```yaml
version: ^0.8.0
scripts:
  test_all:
    command: dart test
    runInPackages:
      - packages/*
```

Package-level `dpk.yaml` files can define package-specific scripts. Root
scripts are inherited by workspace packages, and package scripts take precedence
when names conflict.

Package-level `dpk.yaml` files may only define scripts. Fields such as
`catalog`, `mode`, and `dependency_overrides` are only valid at the workspace
root.

## Catalog and Pubspec Updates

Use the catalog when dependencies should be managed centrally. During `dpk get`,
dpk can update matching dependency entries in root and workspace
`pubspec.yaml` files before running pub. A catalog dependency updates matching
entries in both `dependencies` and `dev_dependencies`; the package must already
exist in the pubspec for dpk to update it.

Example:

```yaml
version: ^0.8.0
catalog:
  environment:
    sdk: ^3.8.0
  version: 1.2.3
  resolution: workspace
  publish_to: none
  homepage: https://example.com/DPK_PACKAGE_NAME
  repository: https://github.com/example/repo/tree/main/DPK_PACKAGE_PATH
  issue_tracker: https://github.com/example/repo/issues
  documentation: https://pub.dev/documentation/DPK_PACKAGE_NAME/DPK_PACKAGE_VERSION/
  topics:
    - dpk
  funding:
    - https://github.com/sponsors/DPK_PACKAGE_NAME
  platforms:
    linux:
    macos:
  dependencies:
    collection: ^1.19.1
sort_pubspec: true
```

Catalog fields parsed by dpk:

- `environment`: replaces `environment`; root and workspace packages.
- `version`: sets workspace package `version`.
- `publish_to`: sets workspace package `publish_to`.
- `homepage`: sets workspace package `homepage`; supports template variables.
- `repository`: sets workspace package `repository`; supports template variables.
- `issue_tracker`: sets workspace package `issue_tracker`; supports template variables.
- `documentation`: sets workspace package `documentation`; supports template variables.
- `topics`: appends missing catalog topics without removing existing topics.
- `funding`: sets workspace package funding URLs; supports template variables.
- `platforms`: sets workspace package `platforms`.
- `resolution`: sets workspace package `resolution`.
- `dependencies`: updates existing matching entries in both `dependencies` and
  `dev_dependencies`; missing dependencies are not added.

Template variables expand per workspace package during `dpk get`:

- `DPK_PACKAGE_PATH`: package path relative to workspace root, such as
  `packages/core`.
- `DPK_PACKAGE_NAME`: package `name` from that package's `pubspec.yaml`, such
  as `core`.
- `DPK_PACKAGE_VERSION`: catalog `version` when configured; otherwise that
  package's existing pubspec version.

Variables can also use `$` prefix, such as `$DPK_PACKAGE_NAME`. Use template
variables in `homepage`, `repository`, `issue_tracker`, `documentation`, and
`funding`.

Catalog dependency values support the same shapes as pubspec dependencies:
version strings, hosted dependencies, SDK dependencies, path dependencies, and
Git dependencies.

Catalog does not manage `name`, `description`, `screenshots`, `false_secrets`,
`ignored_advisories`, `executables`, `flutter`, `dependency_overrides`, or a
separate `dev_dependencies` catalog section.

Use `sort_pubspec: true` to sort pubspec files during `dpk get`. If dpk finds
old `sortPubspec`, `dpk get` migrates it to `sort_pubspec`.

## Project Cache Mode

Project cache mode stores pub packages in a local cache instead of the default
global pub cache:

```yaml
version: ^0.8.0
mode: project
```

When project mode is enabled, dpk sets `PUB_CACHE` for dependency commands and
scripted pub flows that need the project cache.

## Patches

Patch commands require project cache mode:

```yaml
version: ^0.8.0
mode: project
```

Typical patch flow:

```bash
dpk get
dpk patch init
# edit packages under pub_packages
dpk patch generate
dpk patch apply
```

Patch command options:

```bash
dpk patch init --force
dpk patch generate --force
dpk patch generate --patch-dir patches
dpk patch apply --patch-dir patches
dpk patch apply --force
```

Use `--patch-dir` or `-p` to choose the patch directory. Use `--force` with
`patch init` to reinitialize the patch cache, with `patch generate` to skip the
confirmation prompt before replacing patch files, and with `patch apply` only
when it is acceptable to discard local changes in the patch cache before
applying saved patches.

Generated patch files are written under `hosted/` and `git/` inside the patch
directory. Untracked files in the package cache are reported but not converted
to patch files.

## Agent Workflow

When operating dpk for a user:

1. Inspect `dpk.yaml` and `pubspec.yaml` first.
2. Run `dpk skills` when exact CLI behavior is needed.
3. Prefer `dpk add`, `dpk remove`, `dpk get`, and other dpk commands over
   direct `dart pub` calls when the project is configured for dpk.
4. Use `dpk run <script>` for configured workflows.
5. Use `dpk -C <directory>` instead of changing directories when running a
   command in another package.
