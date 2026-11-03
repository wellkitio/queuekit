import 'dart:async';
import 'dart:convert';

import 'package:queuekit/queuekit.dart';
import 'package:test/test.dart';

import 'utils/events.dart';
import 'utils/queues.dart';

void main() {
  group('Given a started store-backed HydratedQueue and a caller database transaction', () {
    late TransactionalOutboxDatabase db;
    late HydratedQueue queue;
    late FakeQueueClock clock;
    late List<String> executionLog;

    setUp(() {
      clock = FakeQueueClock(DateTime.utc(2026, 11, 3, 10));
      executionLog = [];
      db = TransactionalOutboxDatabase(executionLog: executionLog);
      queue = HydratedQueue.store(
        QueueStartListenable()..start(),
        eventSerializers: [OutboxMutationEvent.serializer],
        store: db.store,
        clock: clock,
      );
    });

    tearDown(() => queue.dispose());

    group('When an entity and its queue record are written in one transaction before add', () {
      late OutboxMutationEvent mutation;
      late Completer<void> commitGate;
      late Future<void> transactionFuture;

      setUp(() async {
        commitGate = Completer<void>();
        mutation = OutboxMutationEvent(
          id: 'mut-1',
          entityId: 'todo-1',
          accountId: 'acc-1',
          onRun: () {
            executionLog.add('run:mut-1:entityExists=${db.entities.contains('todo-1')}');
          },
        );

        final record = queue.recordFor(mutation);
        transactionFuture = db.runInTransaction(() async {
          db.stageEntity('todo-1');
          db.stageRecord(record);
          await commitGate.future;
        });
        await Future<void>.delayed(Duration.zero);
      });

      test('Then the event does not run before the transaction commits', () {
        expect(executionLog, isEmpty);
        expect(queue.pendingEvents, isEmpty);
      });

      group('and the transaction commits and add is called with persisted: true', () {
        setUp(() async {
          commitGate.complete();
          await transactionFuture;
          await queue.add(mutation, persisted: true);
          await Future<void>.delayed(Duration.zero);
        });

        test('Then the entity and record committed together before the event ran', () {
          expect(executionLog, [
            'tx:commit(entities: [todo-1], records: [mut-1])',
            'run:mut-1:entityExists=true',
          ]);
        });

        test('Then add with persisted: true does not insert the record a second time', () {
          expect(db.store.insertCount, equals(0));
        });

        test('Then the record is removed from the store once the event succeeds', () {
          expect(db.store.records, isEmpty);
        });
      });
    });

    group('When two dependent events are prepared and committed in one transaction', () {
      late OutboxMutationEvent first;
      late OutboxMutationEvent second;
      late QueueRecord firstRecord;
      late QueueRecord secondRecord;

      setUp(() async {
        queue.startListenable.pause();
        first = OutboxMutationEvent(
          id: 'mut-first',
          entityId: 'todo-1',
          accountId: 'acc-1',
          onRun: () => executionLog.add('run:mut-first'),
        );
        second = OutboxMutationEvent(
          id: 'mut-second',
          entityId: 'todo-1',
          accountId: 'acc-1',
          onRun: () => executionLog.add('run:mut-second'),
        );
        firstRecord = queue.recordFor(first);
        secondRecord = queue.recordFor(second, dependsOn: [first]);
        await db.runInTransaction(() async {
          db.stageEntity('todo-1');
          db.stageRecord(firstRecord);
          db.stageRecord(secondRecord);
        });
        await queue.add(first, persisted: true);
        await queue.add(second, persisted: true);
        await Future<void>.delayed(Duration.zero);
      });

      test('Then both records keep their prepared sequences and dependencies with zero extra store '
          'writes', () {
        expect(db.store.insertCount, equals(0));
        expect(db.store.updateCount, equals(0));
        expect(db.store.records['mut-first']?.sequence, equals(firstRecord.sequence));
        expect(db.store.records['mut-second']?.sequence, equals(secondRecord.sequence));
        expect(firstRecord.sequence, lessThan(secondRecord.sequence));
        expect(db.store.records['mut-second']?.dependsOn, equals({'mut-first'}));
      });

      group('and the queue is started', () {
        setUp(() async {
          queue.startListenable.start();
          await Future<void>.delayed(processingTime);
        });

        test('Then the two events run in sequence order and their records are removed', () {
          expect(executionLog, [
            'tx:commit(entities: [todo-1], records: [mut-first, mut-second])',
            'run:mut-first',
            'run:mut-second',
          ]);
          expect(db.store.records, isEmpty);
        });
      });
    });

    group('When two dependent events are prepared in one transaction and added in reverse order on '
        'a started queue', () {
      setUp(() async {
        final first = OutboxMutationEvent(
          id: 'rev-first',
          entityId: 'todo-1',
          accountId: 'acc-1',
          onRun: () => executionLog.add('run:rev-first'),
        );
        final second = OutboxMutationEvent(
          id: 'rev-second',
          entityId: 'todo-1',
          accountId: 'acc-1',
          onRun: () => executionLog.add('run:rev-second'),
        );
        final firstRecord = queue.recordFor(first);
        final secondRecord = queue.recordFor(second, dependsOn: [first]);
        await db.runInTransaction(() async {
          db.stageEntity('todo-1');
          db.stageRecord(firstRecord);
          db.stageRecord(secondRecord);
        });
        final addSecond = queue.add(second, persisted: true);
        final addFirst = queue.add(first, persisted: true);
        await addFirst;
        await addSecond;
        await Future<void>.delayed(processingTime);
      });

      test('Then the dependency still runs before the dependent', () {
        expect(executionLog, [
          'tx:commit(entities: [todo-1], records: [rev-first, rev-second])',
          'run:rev-first',
          'run:rev-second',
        ]);
        expect(db.store.records, isEmpty);
      });
    });

    group('When a three-event chain (a -> b -> c) is prepared in one transaction and added in '
        'order c, a, b on a started queue', () {
      setUp(() async {
        final a = OutboxMutationEvent(
          id: 'chain-a',
          entityId: 'todo-1',
          accountId: 'acc-1',
          onRun: () => executionLog.add('run:chain-a'),
        );
        final b = OutboxMutationEvent(
          id: 'chain-b',
          entityId: 'todo-1',
          accountId: 'acc-1',
          onRun: () => executionLog.add('run:chain-b'),
        );
        final c = OutboxMutationEvent(
          id: 'chain-c',
          entityId: 'todo-1',
          accountId: 'acc-1',
          onRun: () => executionLog.add('run:chain-c'),
        );
        final recA = queue.recordFor(a);
        final recB = queue.recordFor(b, dependsOn: [a]);
        final recC = queue.recordFor(c, dependsOn: [b]);
        await db.runInTransaction(() async {
          db.stageEntity('todo-1');
          db.stageRecord(recA);
          db.stageRecord(recB);
          db.stageRecord(recC);
        });
        await queue.add(c, persisted: true);
        await queue.add(a, persisted: true);
        await queue.add(b, persisted: true);
        await Future<void>.delayed(processingTime);
      });

      test('Then the chain runs in dependency order a, b, c', () {
        expect(executionLog, [
          'tx:commit(entities: [todo-1], records: [chain-a, chain-b, chain-c])',
          'run:chain-a',
          'run:chain-b',
          'run:chain-c',
        ]);
        expect(db.store.records, isEmpty);
      });
    });

    group('When add with persisted: true is called without a prior recordFor call', () {
      late bool wasInStoreDuringRun;

      setUp(() async {
        wasInStoreDuringRun = false;
        final event = OutboxMutationEvent(
          id: 'unprepared-persisted',
          entityId: 'todo-unprepared',
          accountId: 'acc-1',
          onRun: () {
            wasInStoreDuringRun = db.store.records.containsKey('unprepared-persisted');
          },
        );
        await queue.add(event, persisted: true);
        await Future<void>.delayed(processingTime);
      });

      test('Then the queue persists the record to the store before running the event', () {
        expect(wasInStoreDuringRun, isTrue);
        expect(db.store.insertCount, equals(1));
        expect(db.store.records, isEmpty);
      });
    });

    group('When an event fails permanently and is retained as failed on a strict primary-key '
        'store, and an event with the same id is later added again', () {
      setUp(() async {
        await queue.add(
          OutboxMutationEvent(
            id: 'reused-id',
            entityId: 'todo-reused',
            accountId: 'acc-1',
            failures: 1,
            onRun: () => executionLog.add('run:reused-id:first'),
          ),
        );
        await Future<void>.delayed(processingTime);
        expect(db.store.records['reused-id']?.state, equals(QueueRecordState.failed));

        await queue.add(
          OutboxMutationEvent(
            id: 'reused-id',
            entityId: 'todo-reused',
            accountId: 'acc-1',
            onRun: () => executionLog.add('run:reused-id:second'),
          ),
        );
        await Future<void>.delayed(processingTime);
      });

      test('Then re-adding updates the existing store record without a duplicate-key insert error '
          'and runs the new event', () {
        expect(executionLog, ['run:reused-id:first', 'run:reused-id:second']);
        expect(db.store.insertCount, equals(1));
        expect(db.store.updateCount, greaterThanOrEqualTo(2));
        expect(db.store.records, isEmpty);
      });
    });

    group('When add with persisted: true is called while an earlier save is still in flight on a '
        'strict primary-key store', () {
      late Completer<void> firstRunGate;
      late Completer<void> removeSaveGate;

      setUp(() async {
        firstRunGate = Completer<void>();
        removeSaveGate = Completer<void>();
        final first = OutboxMutationEvent(
          id: 'mut-a',
          entityId: 'todo-a',
          accountId: 'acc-1',
          runGate: firstRunGate.future,
          onRun: () => executionLog.add('run:mut-a'),
        );
        await queue.add(first);
        await pumpEventQueue();

        db.store.nextApplyGate = removeSaveGate.future;
        firstRunGate.complete();
        await pumpEventQueue();

        final second = OutboxMutationEvent(
          id: 'mut-b',
          entityId: 'todo-b',
          accountId: 'acc-1',
          onRun: () => executionLog.add('run:mut-b'),
        );
        final secondRecord = queue.recordFor(second);
        await db.runInTransaction(() async {
          db.stageEntity('todo-b');
          db.stageRecord(secondRecord);
        });
        final addSecond = queue.add(second, persisted: true);
        removeSaveGate.complete();
        await addSecond;
        await pumpEventQueue();
      });

      test('Then the in-flight save does not erase or re-insert the newly persisted record and '
          'both events complete cleanly', () {
        expect(executionLog, [
          'run:mut-a',
          'tx:commit(entities: [todo-b], records: [mut-b])',
          'run:mut-b',
        ]);
        expect(db.store.insertCount, equals(1));
        expect(db.store.records, isEmpty);
        expect(queue.pendingEvents, isEmpty);
      });
    });

    group('When the caller transaction rolls back before committing and calls discardRecord', () {
      late OutboxMutationEvent rolledBack;

      setUp(() async {
        rolledBack = OutboxMutationEvent(
          id: 'mut-rollback',
          entityId: 'todo-rollback',
          accountId: 'acc-1',
          onRun: () => executionLog.add('run:mut-rollback'),
        );
        final record = queue.recordFor(rolledBack);
        await expectLater(
          db.runInTransaction(() {
            db.stageEntity('todo-rollback');
            db.stageRecord(record);
            throw StateError('database constraint failed');
          }),
          throwsStateError,
        );
        queue.discardRecord(rolledBack.id);
        await Future<void>.delayed(Duration.zero);
      });

      test('Then neither the entity nor the queue record is persisted and nothing runs', () {
        expect(db.entities, isEmpty);
        expect(db.store.records, isEmpty);
        expect(executionLog, isEmpty);
      });

      test('Then a later recordFor does not retain a dependency on the discarded record', () {
        final followUp = queue.recordFor(
          OutboxMutationEvent(id: 'mut-followup', entityId: 'todo-2', accountId: 'acc-1'),
          dependsOn: [rolledBack],
        );
        expect(followUp.dependsOn, isEmpty);
      });
    });

    group('When add is called directly without persisted: true on a started queue', () {
      late Completer<void> storeApplyGate;
      late Future<void> addFuture;

      setUp(() async {
        storeApplyGate = Completer<void>();
        db.store.nextApplyGate = storeApplyGate.future;
        final mutation = OutboxMutationEvent(
          id: 'mut-direct',
          entityId: 'todo-direct',
          accountId: 'acc-1',
          onRun: () {
            executionLog.add(
              'run:mut-direct:inStore=${db.store.records.containsKey('mut-direct')}',
            );
          },
        );
        addFuture = queue.add(mutation);
        await Future<void>.delayed(Duration.zero);
      });

      test('Then the event does not run while the store write is still in flight', () {
        expect(executionLog, isEmpty);
      });

      group('and the store write completes', () {
        setUp(() async {
          storeApplyGate.complete();
          await addFuture;
          await Future<void>.delayed(Duration.zero);
        });

        test('Then the event runs only after its record is durable in the store', () {
          expect(executionLog, ['run:mut-direct:inStore=true']);
        });
      });
    });
  });

  group('Given a store-backed HydratedQueue that records every atomic apply batch', () {
    late RecordingQueueStore store;
    late FakeQueueClock clock;
    late HydratedQueue queue;

    setUp(() {
      store = RecordingQueueStore();
      clock = FakeQueueClock(DateTime.utc(2026, 11, 3, 12));
      queue = HydratedQueue.store(
        QueueStartListenable()..start(),
        eventSerializers: [OutboxMutationEvent.serializer],
        store: store,
        clock: clock,
      );
    });

    tearDown(() => queue.dispose());

    group('When a dependency fails once and parks its dependent in the retry queue', () {
      late OutboxMutationEvent first;
      late OutboxMutationEvent dependent;

      setUp(() async {
        first = OutboxMutationEvent(
          id: 'first',
          entityId: 'e1',
          accountId: 'acc-1',
          failures: 1,
          retryConfig: LinearRetryConfig(maxRetries: 2, delay: const Duration(seconds: 10)),
        );
        dependent = OutboxMutationEvent(id: 'dependent', entityId: 'e1', accountId: 'acc-1');
        queue.add(first);
        queue.add(dependent, dependsOn: [first]);
        await Future<void>.delayed(processingTime);
      });

      test('Then both records are inserted together in the first atomic batch', () {
        expect(store.batches.first, [
          isA<QueueRecordInsert>().having((c) => c.record.id, 'id', 'first'),
          isA<QueueRecordInsert>().having((c) => c.record.id, 'id', 'dependent'),
        ]);
      });

      test('Then moving both to the retry queue is a single atomic update batch with no '
          'intermediate delete', () {
        expect(store.batches.last, [
          isA<QueueRecordUpdate>()
              .having((c) => c.record.id, 'id', 'first')
              .having((c) => c.record.state, 'state', QueueRecordState.scheduled)
              .having((c) => c.record.attemptCount, 'attemptCount', 1)
              .having((c) => c.record.awaitingRetry, 'awaitingRetry', isTrue)
              .having(
                (c) => c.record.nextAttemptAt,
                'nextAttemptAt',
                DateTime.utc(2026, 11, 3, 12, 0, 10),
              ),
          isA<QueueRecordUpdate>()
              .having((c) => c.record.id, 'id', 'dependent')
              .having((c) => c.record.state, 'state', QueueRecordState.scheduled)
              .having((c) => c.record.awaitingRetry, 'awaitingRetry', isFalse)
              .having((c) => c.record.dependsOn, 'dependsOn', {'first'}),
        ]);
      });

      test('Then after every batch each event exists in at most one state', () {
        for (final snapshot in store.snapshotsAfterEachBatch) {
          expect(snapshot.keys.toSet().length, equals(snapshot.length));
        }
      });

      group('and the injected clock advances to the retry time', () {
        setUp(() async {
          clock.advance(const Duration(seconds: 10));
          await Future<void>.delayed(processingTime);
        });

        test('Then both events complete and their records are removed', () {
          expect(queue.pendingEvents, isEmpty);
          expect(store.records, isEmpty);
        });
      });
    });
  });

  group(
    'Given a QueueStore containing records for multiple accounts and out-of-order sequences',
    () {
      late InMemoryQueueStore store;
      late FakeQueueClock clock;
      late HydratedQueue queue;
      late List<String> executedIds;

      setUp(() {
        clock = FakeQueueClock(DateTime.utc(2026, 11, 3, 12));
        executedIds = [];
        store = InMemoryQueueStore([
          QueueRecord(
            id: 'acc1-second',
            type: OutboxMutationEvent.typeName,
            eventJson: const {'id': 'acc1-second', 'entityId': 'e2', 'accountId': 'acc-1'},
            sequence: 20,
          ),
          QueueRecord(
            id: 'acc2-first',
            type: OutboxMutationEvent.typeName,
            eventJson: const {'id': 'acc2-first', 'entityId': 'e3', 'accountId': 'acc-2'},
            sequence: 25,
          ),
          QueueRecord(
            id: 'acc1-first',
            type: OutboxMutationEvent.typeName,
            eventJson: const {'id': 'acc1-first', 'entityId': 'e1', 'accountId': 'acc-1'},
            state: QueueRecordState.scheduled,
            nextAttemptAt: DateTime.utc(2026, 11, 3, 11, 59),
            awaitingRetry: true,
            sequence: 10,
          ),
          QueueRecord(
            id: 'acc1-failed',
            type: OutboxMutationEvent.typeName,
            eventJson: const {'id': 'acc1-failed', 'entityId': 'e0', 'accountId': 'acc-1'},
            state: QueueRecordState.failed,
            attemptCount: 3,
            sequence: 1,
            error: 'permanent failure',
          ),
        ]);
        queue = HydratedQueue.store(
          QueueStartListenable(),
          eventSerializers: [OutboxMutationEvent.serializerWithHook((id) => executedIds.add(id))],
          store: store,
          clock: clock,
        );
      });

      tearDown(() => queue.dispose());

      group('When hydrated with a filter for acc-1', () {
        setUp(() async {
          await queue.hydrate(filter: (record) => record.eventJson['accountId'] == 'acc-1');
        });

        test('Then only acc-1 non-terminal records are restored, with due scheduled records '
            'ordered by sequence alongside pending records', () {
          expect(queue.currentQueue.map((e) => e.id), ['acc1-first', 'acc1-second']);
        });

        test('Then a new record prepared after filtered hydrate receives a sequence above the '
            'store-wide maximum', () {
          final nextRecord = queue.recordFor(
            OutboxMutationEvent(id: 'acc1-third', entityId: 'e4', accountId: 'acc-1'),
          );
          expect(nextRecord.sequence, greaterThan(25));
        });

        group('and the queue runs to completion', () {
          setUp(() async {
            queue.startListenable.start();
            await Future<void>.delayed(processingTime);
          });

          test('Then the restored acc-1 events run in sequence order', () {
            expect(executedIds, ['acc1-first', 'acc1-second']);
          });

          test('Then acc-2 records and terminal failed records remain untouched in the store', () {
            expect(store.records.keys, unorderedEquals(['acc2-first', 'acc1-failed']));
            expect(store.records['acc1-failed']?.state, equals(QueueRecordState.failed));
          });
        });
      });
    },
  );

  group('Given a snapshot-backed HydratedQueue with events for multiple accounts', () {
    late String savedCurrent;
    late String savedRetry;
    late HydratedQueue queue;

    setUp(() {
      savedCurrent = jsonEncode([
        {'type': OutboxMutationEvent.typeName, 'id': 'a1', 'entityId': 'e1', 'accountId': 'acc-1'},
        {'type': OutboxMutationEvent.typeName, 'id': 'a2', 'entityId': 'e2', 'accountId': 'acc-2'},
      ]);
      savedRetry = jsonEncode({
        'r2': {
          'type': OutboxMutationEvent.typeName,
          'event': {'id': 'r2', 'entityId': 'e3', 'accountId': 'acc-2'},
          'nextExecutionTime': DateTime.utc(2026, 11, 3, 13).toIso8601String(),
          'awaitingRetry': true,
        },
      });
      queue = HydratedQueue(
        QueueStartListenable(),
        eventSerializers: [OutboxMutationEvent.serializer],
        clock: FakeQueueClock(DateTime.utc(2026, 11, 3, 12)),
        hydrateCurrentQueue: () => savedCurrent,
        hydrateRetryQueue: () => savedRetry,
        saveCurrentQueue: (data) => savedCurrent = data,
        saveRetryQueue: (data) => savedRetry = data,
      );
    });

    tearDown(() => queue.dispose());

    group('When hydrated with a filter for acc-1 and run to completion', () {
      setUp(() async {
        await queue.hydrate(filter: (record) => record.eventJson['accountId'] == 'acc-1');
        queue.startListenable.start();
        await Future<void>.delayed(processingTime);
      });

      test('Then acc-2 snapshot entries in both queues are preserved across saves', () {
        final remainingCurrent = (jsonDecode(savedCurrent) as List).cast<Map<String, dynamic>>();
        final remainingRetry = jsonDecode(savedRetry) as Map<String, dynamic>;

        expect(remainingCurrent.map((e) => e['id']), ['a2']);
        expect(remainingRetry.keys, ['r2']);
      });
    });
  });

  group('Given a store-backed HydratedQueue with a custom retryPolicy and FakeQueueClock', () {
    late InMemoryQueueStore store;
    late FakeQueueClock clock;
    late QueueStartListenable startListenable;
    late HydratedQueue queue;
    late List<EventFailedException> errors;
    late DateTime serverRetryAfter;

    setUp(() {
      store = InMemoryQueueStore();
      clock = FakeQueueClock(DateTime.utc(2026, 11, 3, 15));
      startListenable = QueueStartListenable()..start();
      errors = [];
      serverRetryAfter = DateTime.utc(2026, 11, 3, 15, 2);

      queue = HydratedQueue.store(
        startListenable,
        eventSerializers: [OutboxMutationEvent.serializer],
        store: store,
        clock: clock,
        retryPolicy: (event, error, attemptCount) {
          final message = error.toString();
          if (message.contains('429')) {
            return RetryDecision.retryAt(serverRetryAfter);
          }
          if (message.contains('401')) {
            return const RetryDecision.pause();
          }
          if (message.contains('400')) {
            return const RetryDecision.fail();
          }
          return null;
        },
      );
      queue.listenAll((_) {}, onError: (event, error, stackTrace) => errors.add(error));
    });

    tearDown(() => queue.dispose());

    group('When an event fails with 429 and retryPolicy returns retryAt', () {
      late OutboxMutationEvent event;

      setUp(() async {
        var attempts = 0;
        event = OutboxMutationEvent(
          id: 'rate-limited',
          entityId: 'e1',
          accountId: 'acc-1',
          onRun: () {
            if (++attempts == 1) throw Exception('429 Too Many Requests');
          },
        );
        await queue.add(event);
        await Future<void>.delayed(processingTime);
      });

      test(
        'Then the event is scheduled in the retry queue for the exact Retry-After timestamp',
        () {
          expect(queue.retryQueue['rate-limited']?.nextExecutionTime, equals(serverRetryAfter));
          expect(store.records['rate-limited']?.state, equals(QueueRecordState.scheduled));
          expect(store.records['rate-limited']?.nextAttemptAt, equals(serverRetryAfter));
          expect(store.records['rate-limited']?.attemptCount, equals(1));
        },
      );

      test('Then advancing the clock before Retry-After does not run the event', () async {
        clock.advance(const Duration(minutes: 1, seconds: 59));
        await Future<void>.delayed(processingTime);

        expect(queue.retryQueue, contains('rate-limited'));
      });

      test('Then advancing the clock to Retry-After re-queues and completes the event', () async {
        clock.advance(const Duration(minutes: 2));
        await Future<void>.delayed(processingTime);

        expect(queue.pendingEvents, isEmpty);
        expect(store.records, isEmpty);
      });
    });

    group('When an event fails with 401 and retryPolicy returns pause', () {
      late OutboxMutationEvent authEvent;
      late OutboxMutationEvent trailingEvent;
      late Future<String> waitForAuthEvent;
      late bool tokenRefreshed;

      setUp(() async {
        tokenRefreshed = false;
        authEvent = OutboxMutationEvent(
          id: 'auth-op',
          entityId: 'e1',
          accountId: 'acc-1',
          onRun: () {
            if (!tokenRefreshed) throw Exception('401 Unauthorized');
          },
        );
        trailingEvent = OutboxMutationEvent(id: 'trailing-op', entityId: 'e2', accountId: 'acc-1');
        waitForAuthEvent = queue.waitFor<OutboxMutationEvent, String>(authEvent);
        await queue.add(authEvent);
        await queue.add(trailingEvent, dependsOn: [authEvent]);
        await Future<void>.delayed(processingTime);
      });

      test('Then the queue pauses and keeps the failed event at the front of currentQueue', () {
        expect(startListenable.isStarted, isFalse);
        expect(queue.currentQueue.map((e) => e.id), ['auth-op', 'trailing-op']);
        expect(store.records['auth-op']?.state, equals(QueueRecordState.pending));
        expect(store.records['auth-op']?.attemptCount, equals(1));
        expect(errors.single.willRetry, isTrue);
      });

      group('and the queue is resumed after refreshing credentials', () {
        setUp(() async {
          tokenRefreshed = true;
          startListenable.start();
          await Future<void>.delayed(processingTime);
        });

        test('Then the paused event and its dependent run in order and complete waitFor', () async {
          await expectLater(waitForAuthEvent, completion('auth-op'));
          expect(queue.pendingEvents, isEmpty);
          expect(store.records, isEmpty);
        });
      });
    });

    group('When an event fails permanently via RetryDecision.fail with a dependent event', () {
      setUp(() async {
        final badEvent = OutboxMutationEvent(
          id: 'bad-request',
          entityId: 'e1',
          accountId: 'acc-1',
          onRun: () => throw Exception('400 Bad Request'),
        );
        final dependent = OutboxMutationEvent(
          id: 'dependent-on-bad',
          entityId: 'e1',
          accountId: 'acc-1',
        );
        await queue.add(badEvent);
        await queue.add(dependent, dependsOn: [badEvent]);
        await Future<void>.delayed(processingTime);
      });

      test('Then both events leave the active queue and stay persisted as terminal failed', () {
        expect(queue.pendingEvents, isEmpty);
        expect(store.records['bad-request']?.state, equals(QueueRecordState.failed));
        expect(store.records['bad-request']?.attemptCount, equals(1));
        expect(store.records['bad-request']?.error, contains('400 Bad Request'));
        expect(store.records['dependent-on-bad']?.state, equals(QueueRecordState.failed));
        expect(store.records['dependent-on-bad']?.dependsOn, equals({'bad-request'}));
      });
    });

    group('When an event exhausts its RetryConfig without a custom retryPolicy', () {
      setUp(() async {
        final exhausting = OutboxMutationEvent(
          id: 'exhausting',
          entityId: 'e1',
          accountId: 'acc-1',
          failures: 3,
          retryConfig: LinearRetryConfig(maxRetries: 1, delay: const Duration(seconds: 5)),
        );
        await queue.add(exhausting);
        await Future<void>.delayed(processingTime);
        clock.advance(const Duration(seconds: 5));
        await Future<void>.delayed(processingTime);
      });

      test('Then the exhausted event stays persisted in the store with state failed', () {
        expect(queue.pendingEvents, isEmpty);
        expect(store.records['exhausting']?.state, equals(QueueRecordState.failed));
        expect(store.records['exhausting']?.attemptCount, equals(2));
      });
    });
  });

  group('Given a store-backed HydratedQueue with retainFailedEvents: false and a retryPolicy that '
      'falls back to RetryConfig', () {
    late InMemoryQueueStore store;
    late HydratedQueue queue;

    setUp(() {
      store = InMemoryQueueStore();
      queue = HydratedQueue.store(
        QueueStartListenable()..start(),
        eventSerializers: [OutboxMutationEvent.serializer],
        store: store,
        retainFailedEvents: false,
        retryPolicy: (event, error, attemptCount) {
          if (error.toString().contains('keep')) {
            return const RetryDecision.fail(retainRecord: true);
          }
          return null;
        },
      );
    });

    tearDown(() => queue.dispose());

    test('When an event exhausts its retries via fallback then its record is removed from the '
        'store', () async {
      await queue.add(
        OutboxMutationEvent(id: 'drop-on-fail', entityId: 'e1', accountId: 'acc-1', failures: 1),
      );
      await Future<void>.delayed(processingTime);

      expect(store.records, isEmpty);
    });

    test('When retryPolicy returns RetryDecision.fail(retainRecord: true) then the record is '
        'kept in the store', () async {
      await queue.add(
        OutboxMutationEvent(
          id: 'keep-on-fail',
          entityId: 'e1',
          accountId: 'acc-1',
          onRun: () => throw Exception('keep this failure'),
        ),
      );
      await Future<void>.delayed(processingTime);

      expect(store.records['keep-on-fail']?.state, equals(QueueRecordState.failed));
    });
  });

  group('Given a store-backed HydratedQueue that pauses on 401 without counting the attempt', () {
    late InMemoryQueueStore store;
    late FakeQueueClock clock;
    late QueueStartListenable startListenable;
    late HydratedQueue queue;
    late List<int> policyAttemptCounts;
    late DateTime serverRetryAfter;
    late QueueRecord? recordBeforeFirstRun;

    setUp(() async {
      store = InMemoryQueueStore();
      clock = FakeQueueClock(DateTime.utc(2026, 11, 3, 15));
      startListenable = QueueStartListenable()..start();
      policyAttemptCounts = [];
      serverRetryAfter = DateTime.utc(2026, 11, 3, 15, 2);
      queue = PauseWithoutCountingHydratedQueue.store(
        startListenable,
        eventSerializers: [OutboxMutationEvent.serializer],
        store: store,
        clock: clock,
        retryPolicy: (event, error, attemptCount) {
          policyAttemptCounts.add(attemptCount);
          final message = error.toString();
          if (message.contains('429')) return RetryDecision.retryAt(serverRetryAfter);
          if (message.contains('401')) return const RetryDecision.pause();
          return null;
        },
      );
      queue.listenAll((_) {}, onError: (event, error, stackTrace) {});

      var attempts = 0;
      await queue.add(
        OutboxMutationEvent(
          id: 'auth-op',
          entityId: 'e1',
          accountId: 'acc-1',
          onRun: () {
            attempts++;
            if (attempts == 1) {
              recordBeforeFirstRun = store.records['auth-op'];
              throw Exception('401 Unauthorized');
            }
            if (attempts == 2) throw Exception('429 Too Many Requests');
          },
        ),
      );
      await Future<void>.delayed(processingTime);
    });

    tearDown(() => queue.dispose());

    group('When the event fails with 401 and retryPolicy returns pause', () {
      test('Then the queue pauses and the record stays pending', () {
        expect(startListenable.isStarted, isFalse);
        expect(store.records['auth-op']?.state, equals(QueueRecordState.pending));
      });

      test('Then the retryPolicy receives attemptCount 1', () {
        expect(policyAttemptCounts, [1]);
      });

      test('Then the persisted attemptCount stays at 0 and the record is not updated', () {
        expect(store.records['auth-op']?.attemptCount, equals(0));
        expect(store.records['auth-op'], same(recordBeforeFirstRun));
      });
    });

    group('When the queue is resumed and the event then fails with 429', () {
      setUp(() async {
        startListenable.start();
        await Future<void>.delayed(processingTime);
      });

      test('Then the retryPolicy receives attemptCount 1 again', () {
        expect(policyAttemptCounts, [1, 1]);
      });

      test('Then the record is scheduled with attemptCount 1', () {
        final record = store.records['auth-op'];
        expect(record?.state, equals(QueueRecordState.scheduled));
        expect(record?.nextAttemptAt, equals(serverRetryAfter));
        expect(record?.attemptCount, equals(1));
      });
    });
  });

  group('Given a QueueRecord with all fields populated', () {
    late QueueRecord original;

    setUp(() {
      original = QueueRecord(
        id: 'rec-1',
        type: 'OutboxMutationEvent',
        eventJson: const {
          'id': 'rec-1',
          'nested': ['a', 1],
        },
        state: QueueRecordState.scheduled,
        dependsOn: const {'dep-1'},
        attemptCount: 2,
        nextAttemptAt: DateTime.utc(2026, 11, 3, 16),
        awaitingRetry: true,
        sequence: 42,
        error: 'previous error',
      );
    });

    test('When converted toJson and back with fromJson then the record is equal', () {
      final restored = QueueRecord.fromJson(original.toJson());

      expect(restored, equals(original));
      expect(restored.hashCode, equals(original.hashCode));
    });
  });
}

class OutboxMutationEvent extends Event<String> {
  OutboxMutationEvent({
    required this.id,
    required this.entityId,
    required this.accountId,
    this.failures = 0,
    this.retryConfig,
    this.onRun,
    this.runGate,
  });

  static const typeName = 'OutboxMutationEvent';

  static final serializer = serializerWithHook(null);

  static EventSerializer<OutboxMutationEvent> serializerWithHook(void Function(String id)? onRun) {
    return EventSerializer<OutboxMutationEvent>(
      type: typeName,
      fromJson: (json) => OutboxMutationEvent(
        id: json['id'] as String,
        entityId: json['entityId'] as String,
        accountId: json['accountId'] as String,
        failures: json['failures'] as int? ?? 0,
        retryConfig: json['retryConfig'] == null
            ? null
            : linearRetryConfigSerializer.fromJson(json['retryConfig'] as Map<String, dynamic>),
        onRun: onRun == null ? null : () => onRun(json['id'] as String),
      ),
      toJson: (event) => {
        'id': event.id,
        'entityId': event.entityId,
        'accountId': event.accountId,
        if (event.failures > 0) 'failures': event.failures,
        if (event.retryConfig case final config?)
          'retryConfig': linearRetryConfigSerializer.toJson(config),
      },
    );
  }

  @override
  final String id;

  final String entityId;
  final String accountId;
  final int failures;
  final void Function()? onRun;
  final Future<void>? runGate;

  int _runs = 0;

  @override
  LinearRetryConfig? retryConfig;

  @override
  String get type => typeName;

  @override
  Future<String> run() async {
    onRun?.call();
    if (runGate case final gate?) {
      await gate;
    } else {
      await Future<void>.delayed(Duration.zero);
    }
    _runs++;
    if (_runs <= failures) {
      throw Exception('$id failed on run $_runs');
    }
    return id;
  }
}

class TransactionalOutboxDatabase {
  TransactionalOutboxDatabase({required this.executionLog});

  final List<String> executionLog;
  final entities = <String>{};
  late final store = TransactionalQueueStore();

  final _stagedEntities = <String>[];
  final _stagedRecords = <QueueRecord>[];

  void stageEntity(String entityId) => _stagedEntities.add(entityId);

  void stageRecord(QueueRecord record) => _stagedRecords.add(record);

  Future<void> runInTransaction(Future<void> Function() action) async {
    try {
      await action();
      entities.addAll(_stagedEntities);
      for (final record in _stagedRecords) {
        if (store.committedRecords.containsKey(record.id)) {
          throw StateError('Duplicate primary key ${record.id}');
        }
        store.committedRecords[record.id] = record;
      }
      executionLog.add(
        'tx:commit(entities: [${_stagedEntities.join(', ')}], '
        'records: [${_stagedRecords.map((r) => r.id).join(', ')}])',
      );
    } finally {
      _stagedEntities.clear();
      _stagedRecords.clear();
    }
  }
}

final class TransactionalQueueStore extends QueueStore {
  final committedRecords = <String, QueueRecord>{};
  int insertCount = 0;
  int updateCount = 0;
  Future<void>? nextApplyGate;

  Map<String, QueueRecord> get records => Map.unmodifiable(committedRecords);

  @override
  Iterable<QueueRecord> load({QueueRecordFilter? filter}) {
    final values = filter == null ? committedRecords.values : committedRecords.values.where(filter);
    return values.toList()..sort((a, b) => a.sequence.compareTo(b.sequence));
  }

  @override
  void insert(QueueRecord record) {
    if (committedRecords.containsKey(record.id)) {
      throw StateError('Duplicate primary key on insert: ${record.id}');
    }
    insertCount++;
    committedRecords[record.id] = record;
  }

  @override
  void update(QueueRecord record) {
    if (!committedRecords.containsKey(record.id)) {
      throw StateError('Missing primary key on update: ${record.id}');
    }
    updateCount++;
    committedRecords[record.id] = record;
  }

  @override
  void remove(String id) {
    if (!committedRecords.containsKey(id)) {
      throw StateError('Missing primary key on remove: $id');
    }
    committedRecords.remove(id);
  }

  @override
  Future<void> apply(List<QueueChange> changes) async {
    if (nextApplyGate case final gate?) {
      nextApplyGate = null;
      await gate;
    }
    final snapshot = Map<String, QueueRecord>.of(committedRecords);
    try {
      await super.apply(changes);
    } catch (_) {
      committedRecords
        ..clear()
        ..addAll(snapshot);
      rethrow;
    }
  }
}

final class RecordingQueueStore extends QueueStore {
  final _records = <String, QueueRecord>{};
  final batches = <List<QueueChange>>[];
  final snapshotsAfterEachBatch = <Map<String, QueueRecord>>[];

  Map<String, QueueRecord> get records => Map.unmodifiable(_records);

  @override
  Iterable<QueueRecord> load({QueueRecordFilter? filter}) {
    final values = filter == null ? _records.values : _records.values.where(filter);
    return values.toList()..sort((a, b) => a.sequence.compareTo(b.sequence));
  }

  @override
  void insert(QueueRecord record) {
    _records[record.id] = record;
  }

  @override
  void update(QueueRecord record) {
    _records[record.id] = record;
  }

  @override
  void remove(String id) {
    _records.remove(id);
  }

  @override
  Future<void> apply(List<QueueChange> changes) async {
    batches.add(List<QueueChange>.unmodifiable(changes));
    await super.apply(changes);
    snapshotsAfterEachBatch.add(Map<String, QueueRecord>.unmodifiable(Map.of(_records)));
  }
}

/// A store-backed [HydratedQueue] whose paused attempts are not counted.
final class PauseWithoutCountingHydratedQueue extends HydratedQueue with PauseWithoutCounting {
  PauseWithoutCountingHydratedQueue.store(
    super.startListenable, {
    required super.eventSerializers,
    required super.store,
    super.clock,
    super.retryPolicy,
  }) : super.store();
}
