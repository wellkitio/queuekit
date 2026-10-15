# QueueKit

[![pub package](https://img.shields.io/pub/v/queuekit.svg)](https://pub.dev/packages/queuekit)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/wellkitio/queuekit/blob/main/packages/queuekit/LICENSE)

A task queue for Dart and Flutter. Queue up units of work as events, run them one at a time in
order, retry the ones that fail, keep dependent events in order, and persist the whole queue so
it survives an app restart.

## Features

- **Sequential processing**: events run one at a time, in the order they were added.
- **Start and pause**: nothing runs until you say so, and you can pause at any time.
- **Typed results**: listen to the results of all events, of one event type, or wait for a single
  event.
- **Retries**: linear and exponential backoff out of the box, or bring your own strategy.
- **Dependent events**: an event can depend on other pending events; it runs after them and waits
  with them through retries, so their order is preserved.
- **Queries**: look up what is pending by id, type or any predicate.
- **Persistence**: `HydratedQueue` saves the queue through callbacks you provide and restores it on
  the next launch, including retries in flight and dependencies.

## Installation

```sh
dart pub add queuekit
# or, in a Flutter project
flutter pub add queuekit
```

QueueKit requires Dart 3.11 or later and has no Flutter dependency.

## Quick start

```dart
import 'package:queuekit/queuekit.dart';

class SendMessage extends Event<String> {
  SendMessage(this.text) : id = 'send-${_created++}';

  static int _created = 0;

  // Ids must be unique among pending events.
  @override
  final String id;

  @override
  String get type => 'SendMessage';

  final String text;

  @override
  RetryConfig? retryConfig = LinearRetryConfig(maxRetries: 3, delay: const Duration(seconds: 2));

  @override
  Future<String> run() async {
    // Do the actual work, for example an HTTP call. Throw to fail the event.
    return 'sent: $text';
  }
}

void main() async {
  final startListenable = QueueStartListenable();
  final queue = Queue(startListenable);

  queue.listenWhere<SendMessage, String>(
    (result) => print('${result.event.text} -> ${result.result}'),
    onError: (event, error, stackTrace) => print('${event.text} failed: ${error.error}'),
  );

  queue.add(SendMessage('hello'));
  queue.add(SendMessage('world'));

  startListenable.start(); // Events start running here.

  final event = SendMessage('!');
  queue.add(event);
  print(await queue.waitFor<SendMessage, String>(event)); // sent: !
}
```

## Events

An event is a unit of work. Extend `Event<T>` where `T` is the type of the result `run` produces.

```dart
abstract class Event<T extends Object?> {
  String get id;
  String get type;
  RetryConfig? get retryConfig;
  Future<T> run();
}
```

- `id` identifies the event while it is pending. **It must be unique among pending events**: the
  retry queue, dependencies and `findEvent` are all keyed by it. Generate one per instance, for
  example with [`package:uuid`](https://pub.dev/packages/uuid), and persist it with the event if you
  use a `HydratedQueue`.
- `type` names the kind of event. `HydratedQueue` uses it to pick the serializer for the event.
- `retryConfig` decides what happens when `run` throws. Return `null` to never retry.
- `run` does the work. Throwing fails the event; the returned value is the event's result.

## The queue

```dart
final startListenable = QueueStartListenable();
final queue = Queue(startListenable);
```

A `Queue` processes events one at a time, in the order they were added, while it is started.
`QueueStartListenable` controls that:

| Member | Effect |
| --- | --- |
| `start()` | Starts processing. Events added while the queue is started run right away. |
| `pause()` | Stops processing after the event that is currently running. Events can still be added. |
| `isStarted` | Whether the queue is currently started. |

A queue starts paused. Set up your listeners, add your events, then call `start()`; a listener
added later misses the results that were already emitted. With a `HydratedQueue`, call `hydrate()`
before `start()` so restored events run before new ones.

`QueueStartListenable` is a [`StateNotifier<bool>`](https://pub.dev/packages/state_notifier), so it
can be driven by connectivity, authentication state or anything else your app knows about.

### Adding events

```dart
queue.add(event);
queue.add(event, dependsOn: [otherEvent]); // See "Dependent events" below.
```

`add` appends the event to the end of the queue. Adding to a started queue that is idle starts it
immediately.

## Listening for results

`queue.results` is a broadcast `Stream` of `QueueListenerResult`, a record of
`(event: ..., result: ...)`. Every successful run emits one, and every failure is a stream error.
The typed helpers below are usually more convenient than listening to it directly.

```dart
// Every event, untyped.
queue.listenAll((result) {
  print('${result.event.type} finished with ${result.result}');
});

// Only events of one type, with the event and result typed accordingly.
queue.listenWhere<SendMessage, String>((result) {
  final SendMessage event = result.event;
  final String text = result.result;
});

// A single event. Completes with its result once it has run, or with its EventFailedException
// if it fails permanently. A failure that is going to be retried does not complete it.
final String text = await queue.waitFor<SendMessage, String>(event);
```

`waitFor` matches the event by id on the result stream, so call it while the event is still
pending, or before adding it. If the event has already finished, or is never added, the future
never completes.

### Errors

When `run` throws, the queue emits an `EventFailedException` on the stream. It carries the `event`,
the original `error`, its `stackTrace` and `willRetry`, which tells whether the queue is going to
retry the event. The `onError` callbacks of `listenAll` and `listenWhere` receive it as a typed
`EventFailedException`, together with the failed event and the stack trace:

```dart
queue.listenWhere<SendMessage, String>(
  (result) {},
  onError: (SendMessage event, EventFailedException exception, StackTrace stackTrace) {
    final outcome = exception.willRetry ? 'will be retried' : 'gave up';
    print('${event.text} failed with ${exception.error}, $outcome');
  },
);
```

`listenWhere` only reports errors for events of the type it listens to. `results.listen` receives
the `EventFailedException` like any stream error.

An error is emitted for every failed attempt, so an event that is retried twice before it succeeds
produces two errors and then one result.

## Retries

Give an event a `RetryConfig` and the queue retries it when `run` throws:

```dart
// Waits delay × retryCount: 1s, 2s, 3s, ...
LinearRetryConfig(maxRetries: 3, delay: const Duration(seconds: 1));

// Waits delay × multiplier ^ retryCount: 2s, 4s, 8s, ...
ExponentialBackoffRetryConfig(maxRetries: 3, delay: const Duration(seconds: 1), multiplier: 2);
```

- When an event fails and has retries left, it moves to the `retryQueue`. Once the delay has passed
  it is added to the **end** of the queue again, so other events may run in between.
- `maxRetries` is the number of retries after the first attempt. A negative value retries forever;
  `retryCount` then stays at 0, so the built-in configs wait `minimumDurationForRetry(0)`, which
  is zero, between attempts. Use a custom `RetryConfig` for unlimited retries with a delay.
- When an event fails with no retries left it is dropped after its last `EventFailedException`.
- `retryCount` lives on the config instance, so share a config between events only if you want
  them to share a retry budget. `canRetry` tells whether a retry is left.

To write your own strategy, extend `RetryConfig` and implement `minimumDurationForRetry` and
`serializer`. A `HydratedQueue` uses the serializer to persist the config with its event, so
include `retryCount`; if you never persist events it may simply throw:

```dart
final class JitteredRetryConfig extends RetryConfig {
  JitteredRetryConfig({required super.maxRetries});

  @override
  Duration minimumDurationForRetry(int retryCount) {
    return Duration(milliseconds: 500 * retryCount + Random().nextInt(500));
  }

  @override
  JsonSerializer<JitteredRetryConfig> get serializer => JsonSerializer(
    fromJson: (json) => JitteredRetryConfig(maxRetries: json['maxRetries'] as int)
      ..retryCount = json['retryCount'] as int? ?? 0,
    toJson: (config) => {'maxRetries': config.maxRetries, 'retryCount': config.retryCount},
  );
}
```

## Querying pending events

Sometimes you need to know what is already queued, for example to avoid queueing the same work
twice or to find an event to depend on.

```dart
// Everything that has not finished yet: the current queue in run order (including the running
// event), followed by the retry queue in the order its events were added to it.
final Iterable<Event> pending = queue.pendingEvents;

// By id.
final Event? event = queue.findEvent(uploadId);

// By type, optionally narrowed down with a predicate.
final uploads = queue.findEvents<UploadPhoto>();
final upload = queue.findEvents<UploadPhoto>(where: (e) => e.photoId == photoId).firstOrNull;
```

The lower-level `currentQueue` (a `List<Event>`) and `retryQueue` (a map from id to the event and
the time of its next attempt) are also available as read-only views.

## Dependent events

Retries move an event to the end of the queue, which breaks ordering between events that belong
together. Say `UploadPhoto` must finish before `SharePhoto`: if the upload fails and is retried, the
share would run first. Declare the dependency when adding the event and the queue keeps them in
order:

```dart
final upload = UploadPhoto(photoId);
queue.add(upload);
queue.add(SharePhoto(photoId), dependsOn: [upload]);
```

The rules:

- A dependent event runs after its dependencies, though not necessarily right after them:
  independent events may run in between. Dependencies must already be pending when the dependent
  is added, so they are ahead of it in the queue anyway; the declaration only changes anything
  when a dependency fails.
- **If a dependency fails and is going to be retried, every event that depends on it, directly or
  through other dependents, moves to the retry queue with it.** When the dependency is retried they
  are all re-queued in their original order, right behind it. Events that do not depend on it keep
  running in the meantime.
- Adding an event that depends on an event which is already waiting for a retry puts it straight
  into the retry queue, behind the dependency.
- **If a dependency fails permanently**, because it has no `RetryConfig` or no retries left, its
  dependents do not run. Each fails with an `EventFailedException` whose `error` is a
  `DependencyFailedException` naming the `dependency` and the `error` it failed with. Further
  dependents down the chain fail the same way, each naming its direct dependency.
- Events in `dependsOn` that are not pending (they already finished, or were never added) are
  ignored, so it is safe to depend on work that may already be done.
- An event can depend on several events, and dependents can have dependents of their own.

Dependencies are usually discovered with a query:

```dart
void sharePhoto(String photoId) {
  final upload = queue.findEvents<UploadPhoto>(where: (e) => e.photoId == photoId).firstOrNull;
  queue.add(SharePhoto(photoId), dependsOn: [if (upload != null) upload]);
}
```

Handle a failed dependency like any other failure:

```dart
queue.listenWhere<SharePhoto, Object?>(
  (result) {},
  onError: (event, exception, stackTrace) {
    if (exception.error case DependencyFailedException(:final dependency, :final error)) {
      print('Not sharing ${event.photoId}: ${dependency.type} failed with $error');
    }
  },
);
```

`HydratedQueue` persists dependencies along with the events, so they survive a restart.

## Persistence with HydratedQueue

`HydratedQueue` is a `Queue` that saves itself every time it changes and can restore itself on the
next launch. You provide the storage; it can be anything that stores a string.

```dart
final prefs = await SharedPreferences.getInstance();

final queue = HydratedQueue(
  startListenable,
  eventSerializers: {
    'UploadPhoto': (
      fromJson: (json) => UploadPhoto.fromJson(json),
      toJson: (event) => (event as UploadPhoto).toJson(),
    ),
    'SharePhoto': (
      fromJson: (json) => SharePhoto.fromJson(json),
      toJson: (event) => (event as SharePhoto).toJson(),
    ),
  },
  saveCurrentQueue: (data) => prefs.setString('currentQueue', data),
  hydrateCurrentQueue: () => prefs.getString('currentQueue'),
  saveRetryQueue: (data) => prefs.setString('retryQueue', data),
  hydrateRetryQueue: () => prefs.getString('retryQueue'),
);

await queue.hydrate(); // Restore first...
startListenable.start(); // ...then start.
```

- `eventSerializers` maps each event `type` to a `fromJson`/`toJson` pair. Events whose type has no
  serializer are not persisted.
- `toJson` must include everything needed to rebuild the event, **including its `id` and retry
  configuration**. The built-in retry configs ship with serializers
  (`linearRetryConfigSerializer`, `exponentialBackoffRetryConfigSerializer`); custom ones expose
  theirs through `RetryConfig.serializer`.
- The save callbacks may be synchronous or asynchronous. The hydrate callbacks return the last
  saved string, or `null` when nothing was saved yet.
- `hydrate` restores the current queue, then the retry queue. Retries whose time has already come
  are placed on the current queue; the others wait for their turn. Dependencies are restored too.
  Call it once, before `start()`.
- The built-in retry config serializers include `retryCount`, so a restored event continues its
  retry budget and backoff where it left off. Do the same in a custom `RetryConfig.serializer`.
- Changes made in the same synchronous run are saved together, and saves are written one at a
  time, in the order they happened, even when the storage is slow. `add` returns a future that
  completes once the change is saved and fails if a save callback throws.

### Storage format

The current queue is saved as a JSON array, one object per event, in queue order:

```json
[
  {"photoId": "p1", "id": "e1", "retryConfig": {"maxRetries": 3, "delay": 1000, "retryCount": 0}, "type": "UploadPhoto"},
  {"photoId": "p1", "id": "e2", "type": "SharePhoto", "dependsOn": ["e1"]}
]
```

Each object is the event's `toJson` output plus `id`, `type` and, when present, `dependsOn`. The
whole object is passed back to `fromJson`.

The retry queue is saved as a JSON object keyed by event id, in the order the events entered the
retry queue:

```json
{
  "e1": {"type": "UploadPhoto", "event": {"photoId": "p1", "id": "e1", "retryConfig": {"maxRetries": 3, "delay": 1000, "retryCount": 1}}, "nextExecutionTime": "2026-10-15T10:00:00.000Z", "awaitingRetry": true},
  "e2": {"type": "SharePhoto", "event": {"photoId": "p1", "id": "e2"}, "nextExecutionTime": "2026-10-15T10:00:00.000Z", "awaitingRetry": false, "dependsOn": ["e1"]}
}
```

Here only the `event` object is passed back to `fromJson`, which is why `toJson` has to include
the id itself. `awaitingRetry` distinguishes an event waiting for its own retry from one that is
only waiting for a dependency.

## Disposing

```dart
queue.dispose();
```

`dispose` cancels pending retries, closes the result stream, disposes the `QueueStartListenable`
and clears the queue. Adding to or listening to the queue afterwards throws a `StateError`. A
`HydratedQueue` does not save on dispose, so its persisted events are restored on the next launch.

## API overview

| Type | Purpose |
| --- | --- |
| `Event<T>` | A unit of work with an `id`, a `type`, an optional `retryConfig` and a `run` method. |
| `Queue` | Runs events in order. `add`, `pendingEvents`, `findEvent`, `findEvents`, `currentQueue`, `retryQueue`, `startListenable`, `results`, `listenAll`, `listenWhere`, `waitFor`, `dispose`. |
| `HydratedQueue` | A `Queue` that persists itself through callbacks and restores with `hydrate`. |
| `QueueStartListenable` | Starts and pauses a queue: `start`, `pause`, `isStarted`. |
| `RetryConfig` | Base class for retry strategies: `maxRetries`, `retryCount`, `canRetry`, `retry`, `minimumDurationForRetry`, `minimumDurationForCurrentRetry`, `serializer`. |
| `LinearRetryConfig` | Retries after `delay × retryCount`. |
| `ExponentialBackoffRetryConfig` | Retries after `delay × multiplier ^ retryCount`. |
| `JsonSerializer<T>` | A `fromJson`/`toJson` pair, used for retry configs. |
| `EventSerializers` | The map of event type to serializer pair that `HydratedQueue` takes. |
| `QueueListenerResult<T, U>` | The `(event, result)` record emitted for each successful run. |
| `EventFailedException` | Emitted on `results` when an event fails; carries the `event`, `error`, `stackTrace` and `willRetry`. |
| `DependencyFailedException` | The `error` of a dependent that could not run because its `dependency` failed. |
| `RetryExceededException` | Thrown by `RetryConfig.retry` when called with no retries left. |

## Example

The [example](https://github.com/wellkitio/queuekit/tree/main/packages/queuekit/example) is a
Flutter app that persists a `HydratedQueue` with `shared_preferences`.

## License

MIT. See [LICENSE](https://github.com/wellkitio/queuekit/blob/main/packages/queuekit/LICENSE).
