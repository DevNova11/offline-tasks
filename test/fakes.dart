import 'dart:async';

import 'package:offline_tasks/data/remote_store.dart';
import 'package:offline_tasks/models/task.dart';

/// In-memory server with the same conditional-write semantics as the
/// Firestore implementation, plus switches to inject failures.
class InMemoryRemote implements RemoteTaskStore {
  final _docs = <String, Map<String, RemoteTask>>{};
  int _clock = 1000;
  final _changes = StreamController<void>.broadcast();

  /// Next push throws before touching the server.
  bool failNextPush = false;

  /// Next push is applied on the server, then the response is "lost".
  bool loseNextResponse = false;
  bool offline = false;
  bool _dropped = false;
  int pushCalls = 0;

  Map<String, RemoteTask> _col(String uid) => _docs.putIfAbsent(uid, () => {});
  RemoteTask? doc(String uid, String id) => _col(uid)[id];
  int count(String uid) => _col(uid).length;

  @override
  Future<PushResult> push({
    required String uid,
    required Task task,
    required int baseRev,
    required String opId,
  }) async {
    pushCalls++;
    if (offline) throw RemoteUnavailable('offline');
    if (failNextPush) {
      failNextPush = false;
      throw RemoteUnavailable('simulated network failure');
    }
    final current = _col(uid)[task.id];
    if (current != null && current.lastOpId == opId) {
      return PushApplied(current.rev, replayed: true);
    }
    if ((current?.rev ?? 0) != baseRev) return PushConflict(current!);
    _col(uid)[task.id] = RemoteTask(
      task: task,
      rev: baseRev + 1,
      serverUpdatedAtMs: ++_clock,
      lastOpId: opId,
    );
    _changes.add(null);
    if (loseNextResponse) {
      loseNextResponse = false;
      _dropped = true;
      throw RemoteUnavailable('connection dropped before the reply');
    }
    return PushApplied(baseRev + 1);
  }

  @override
  Future<List<RemoteTask>> fetchChangedSince(String uid, int cursorMs) async {
    if (offline) throw RemoteUnavailable('offline');
    if (_dropped) {
      _dropped = false; // the connection is still down for this cycle
      throw RemoteUnavailable('connection dropped');
    }
    return _col(uid).values.where((r) => r.serverUpdatedAtMs >= cursorMs).toList()
      ..sort((a, b) => a.serverUpdatedAtMs.compareTo(b.serverUpdatedAtMs));
  }

  @override
  Stream<List<RemoteTask>> watchChangedSince(String uid, int cursorMs) =>
      const Stream.empty();

  @override
  Future<void> simulateRemoteEdit(
      String uid, String taskId, Task Function(Task) edit) async {
    final cur = _col(uid)[taskId]!;
    _col(uid)[taskId] = RemoteTask(
      task: edit(cur.task),
      rev: cur.rev + 1,
      serverUpdatedAtMs: ++_clock,
      lastOpId: 'sim',
    );
  }
}
