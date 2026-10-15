# QueueKit

[![pub package](https://img.shields.io/pub/v/queuekit.svg)](https://pub.dev/packages/queuekit)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](packages/queuekit/LICENSE)

A persistent task queue for Dart and Flutter. Queue up work as events, run them one at a time in
order, retry failures, keep dependent events in order, and persist the queue across app restarts.

```dart
final startListenable = QueueStartListenable();
final queue = Queue(startListenable);

queue.listenWhere<UploadPhoto, String>((result) => print('Uploaded to ${result.result}'));

final upload = UploadPhoto(photoId);
queue.add(upload);
queue.add(SharePhoto(photoId), dependsOn: [upload]); // Runs after the upload, even if it is retried.

startListenable.start();
```

## Packages

| Package | Description | |
| --- | --- | --- |
| [`queuekit`](packages/queuekit) | The queue, retry strategies and `HydratedQueue` persistence. | [![pub package](https://img.shields.io/pub/v/queuekit.svg)](https://pub.dev/packages/queuekit) |

The full documentation, with examples for every feature, is in the
[package README](packages/queuekit/README.md). A Flutter example app lives in
[`packages/queuekit/example`](packages/queuekit/example).

## Development

This is a [pub workspace](https://dart.dev/tools/pub/workspaces) managed with
[dpk](https://pub.dev/packages/dpk). Tool versions are pinned in [`.tool-versions`](.tool-versions)
for [asdf](https://asdf-vm.com).

```sh
asdf install          # Flutter (which provides the Dart SDK) and Node.js
dart pub global activate dpk

dpk get               # Resolve dependencies for every package
dpk run analyze       # Analyze every package
dpk run format        # Format every package
dpk run test          # Test every package
```

Scripts are defined in [`dpk.yaml`](dpk.yaml) and run from the repository root. The dpk agent skill
for AI coding assistants is checked in under [`skills/dpk`](skills/dpk) and installed with
`npx skills experimental_install`.

### Layout

```
packages/queuekit/           The published package
packages/queuekit/example/   Flutter example app
packages/queuekit/test/      Tests, written in Given/When/Then style
```

### Conventions

- Commits follow [Conventional Commits](https://www.conventionalcommits.org); `!` marks a breaking
  change.
- Tests are structured as `Given … / When … / Then …` groups with assertion-only cases.
- Every user-facing change gets an entry in [`CHANGELOG.md`](CHANGELOG.md) and in the package's
  [`CHANGELOG.md`](packages/queuekit/CHANGELOG.md).

## License

MIT. See [LICENSE](packages/queuekit/LICENSE).
