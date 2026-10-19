import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:offline_tasks/data/local_store.dart';
import 'package:offline_tasks/data/task_repository.dart';
import 'package:offline_tasks/models/sync_log_entry.dart';
import 'package:offline_tasks/models/task.dart';
import 'package:offline_tasks/sync/sync_engine.dart';

import 'fakes.dart';

/// One simulated phone: its own Hive boxes, repository and sync engine.
class Device {
  Device._(this.store, this.repo, this.engine, this.prefix);

  final LocalStore store;
  final TaskRepository repo;
  final SyncEngine engine;
  final String prefix;
  bool online = true;

  static Future<Device> open(String prefix, InMemoryRemote remote,
      {String uid = 'user1'}) async {
    final store = await LocalStore.open(prefix: prefix);
    final repo = TaskRepository(store);
    late Device d;
    final engine = SyncEngine(
      repo: repo,
      store: store,
      remote: remote,
      isOnline: () => d.online,
      currentUid: () => uid,
      debounce: const Duration(hours: 1), // tests call syncNow explicitly
      period: const Duration(hours: 1),
    );
    d = Device._(store, repo, engine, prefix);
    return d;
  }

  Task byTitle(String t) => repo.tasks.firstWhere((x) => x.title == t);
}

void main() {
  late Directory dir;
  late InMemoryRemote remote;
  var n = 0;
  String prefix() => 'd${n++}_';

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('offline_tasks_test');
    Hive.init(dir.path);
    remote = InMemoryRemote();
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('changes made offline are queued and uploaded when back online', () async {
    final d = await Device.open(prefix(), remote);
    d.online = false;
    await d.engine.start();

    await d.repo.create(title: 'Offline task');
    final t = d.byTitle('Offline task');
    await d.repo.update(t.copyWith(priority: Priority.high));
    expect(d.repo.pendingCount, 1, reason: 'edits to one task coalesce');
    await d.engine.syncNow();
    expect(remote.count('user1'), 0);
    expect(d.engine.phase, SyncPhase.offline);

    d.online = true;
    await d.engine.syncNow();
    expect(d.repo.pendingCount, 0);
    expect(remote.doc('user1', t.id)!.task.priority, Priority.high);
    expect(remote.doc('user1', t.id)!.rev, 1);
  });

  test('failed uploads are retried with backoff', () async {
    final d = await Device.open(prefix(), remote);
    await d.repo.create(title: 'Flaky');
    remote.failNextPush = true;
    await d.engine.syncNow();

    final rec = d.repo.recordOf(d.byTitle('Flaky').id)!;
    expect(rec.pending!.attempts, 1);
    expect(rec.pending!.nextAttemptAt!.isAfter(DateTime.now()), isTrue);
    expect(d.engine.phase, SyncPhase.error);
    expect(d.engine.log.any((e) => e.kind == SyncLogKind.retry), isTrue);

    await d.engine.syncNow(); // still backing off: not retried yet
    expect(d.repo.pendingCount, 1);
    await d.engine.syncNow(force: true);
    expect(d.repo.pendingCount, 0);
    expect(remote.count('user1'), 1);
  });

  test('a lost server reply does not create a duplicate', () async {
    final d = await Device.open(prefix(), remote);
    await d.repo.create(title: 'Once');
    remote.loseNextResponse = true;
    await d.engine.syncNow(); // applied on server, but we think it failed
    expect(d.repo.pendingCount, 1);

    await d.engine.syncNow(force: true);
    expect(d.repo.pendingCount, 0);
    expect(remote.count('user1'), 1);
    expect(remote.doc('user1', d.byTitle('Once').id)!.rev, 1,
        reason: 'the retry was recognised, not written again');
    expect(d.engine.log.first.message, contains('recovered'));
  });

  test('queued changes survive an app restart', () async {
    final p = prefix();
    var d = await Device.open(p, remote);
    d.online = false;
    await d.repo.create(title: 'Before crash');
    await Hive.close(); // "kill" the app

    d = await Device.open(p, remote);
    expect(d.repo.tasks.single.title, 'Before crash');
    expect(d.repo.pendingCount, 1);
    await d.engine.start(); // kicks off a sync in the background
    while (d.engine.isSyncing) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(d.engine.log.any((e) => e.kind == SyncLogKind.recovery), isTrue);
    expect(d.repo.pendingCount, 0);
    expect(remote.count('user1'), 1);
  });

  test('two devices editing different fields offline both keep their edits', () async {
    final a = await Device.open(prefix(), remote);
    final b = await Device.open(prefix(), remote);
    await a.repo.create(title: 'Shared');
    await a.engine.syncNow();
    await b.engine.syncNow();
    final id = a.byTitle('Shared').id;

    a.online = b.online = false;
    await a.repo.update(a.repo.recordOf(id)!.task.copyWith(title: 'Shared (renamed)'));
    await b.repo.update(b.repo.recordOf(id)!.task.copyWith(priority: Priority.high));

    a.online = b.online = true;
    await a.engine.syncNow();
    await b.engine.syncNow(); // conflict detected and merged here
    await a.engine.syncNow(); // a receives the merged result

    for (final d in [a, b]) {
      final t = d.repo.recordOf(id)!.task;
      expect(t.title, 'Shared (renamed)');
      expect(t.priority, Priority.high);
      expect(d.repo.pendingCount, 0);
    }
    expect(remote.count('user1'), 1);
    expect(b.engine.log.any((e) => e.kind == SyncLogKind.conflict), isTrue);
  });

  test('same field edited on two devices: last edit wins everywhere', () async {
    final a = await Device.open(prefix(), remote);
    final b = await Device.open(prefix(), remote);
    await a.repo.create(title: 'Original');
    await a.engine.syncNow();
    await b.engine.syncNow();
    final id = a.byTitle('Original').id;

    a.online = b.online = false;
    await a.repo.update(a.repo.recordOf(id)!.task.copyWith(title: 'From A'));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await b.repo.update(b.repo.recordOf(id)!.task.copyWith(title: 'From B'));

    a.online = b.online = true;
    await b.engine.syncNow();
    await a.engine.syncNow(); // a's older edit loses
    await b.engine.syncNow();

    expect(a.repo.recordOf(id)!.task.title, 'From B');
    expect(b.repo.recordOf(id)!.task.title, 'From B');
    expect(remote.doc('user1', id)!.task.title, 'From B');
  });

  test('deletions sync as tombstones', () async {
    final a = await Device.open(prefix(), remote);
    final b = await Device.open(prefix(), remote);
    await a.repo.create(title: 'Doomed');
    await a.engine.syncNow();
    await b.engine.syncNow();
    expect(b.repo.tasks, hasLength(1));

    await a.repo.delete(a.byTitle('Doomed'));
    await a.engine.syncNow();
    await b.engine.syncNow();
    expect(b.repo.tasks, isEmpty);
  });

  test('completing a recurring task on two devices makes one next occurrence', () async {
    final a = await Device.open(prefix(), remote);
    final b = await Device.open(prefix(), remote);
    await a.repo.create(
      title: 'Water plants',
      dueAt: DateTime.now().add(const Duration(hours: 1)),
      recurrence: Recurrence.daily,
    );
    await a.engine.syncNow();
    await b.engine.syncNow();

    a.online = b.online = false;
    await a.repo.setCompleted(a.byTitle('Water plants'), true);
    await b.repo.setCompleted(b.byTitle('Water plants'), true);
    a.online = b.online = true;
    await a.engine.syncNow();
    await b.engine.syncNow();
    await a.engine.syncNow();

    expect(remote.count('user1'), 2, reason: 'original + one shared follow-up');
    expect(a.repo.tasks.where((t) => !t.completed), hasLength(1));
    expect(b.repo.tasks.where((t) => !t.completed), hasLength(1));
  });

  test('signing in to another account re-uploads local tasks there', () async {
    final p = prefix();
    var d = await Device.open(p, remote, uid: 'guest');
    await d.repo.create(title: 'Mine');
    await d.engine.syncNow();
    expect(remote.count('guest'), 1);
    await Hive.close();

    d = await Device.open(p, remote, uid: 'real-account');
    await d.engine.syncNow();
    expect(remote.count('real-account'), 1);
    expect(d.repo.pendingCount, 0);
  });
}
