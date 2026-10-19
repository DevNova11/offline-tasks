import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/local_store.dart';
import '../data/remote_store.dart';
import '../data/task_repository.dart';
import '../models/local_record.dart';
import '../models/sync_log_entry.dart';
import '../models/task.dart';
import 'merge.dart';

enum SyncPhase { idle, syncing, offline, waitingForAccount, error }

/// Moves changes between the local store and the server.
///
/// One cycle = push every queued change (oldest first), then pull everything
/// the server changed since the last pull. Cycles run when the app starts,
/// when connectivity comes back, shortly after any local edit, every 30 s
/// while online, and on demand. Only one cycle runs at a time.
class SyncEngine extends ChangeNotifier {
  SyncEngine({
    required this._repo,
    required this._store,
    required this._remote,
    required this._isOnline,
    required this._currentUid,
    Duration debounce = const Duration(milliseconds: 600),
    this._period = const Duration(seconds: 30),
  }) : _debounceDelay = debounce;

  final TaskRepository _repo;
  final LocalStore _store;
  final RemoteTaskStore _remote;
  final bool Function() _isOnline;
  final String? Function() _currentUid;
  final Duration _debounceDelay;
  final Duration _period;

  static const _maxConflictRetries = 3;

  SyncPhase _phase = SyncPhase.idle;
  SyncPhase get phase => _phase;
  String? _lastError;
  String? get lastError => _lastError;
  DateTime? get lastSyncAt => _store.lastSyncAt;
  bool get isSyncing => _phase == SyncPhase.syncing;

  bool _running = false;
  bool _rerun = false;
  Timer? _debounce;
  Timer? _ticker;
  StreamSubscription<List<RemoteTask>>? _watch;
  String? _watchUid;

  /// Starts background syncing and resumes anything left from last session.
  Future<void> start() async {
    final unfinished = _repo.pendingQueue.length;
    if (unfinished > 0) {
      await _log(SyncLogKind.recovery,
          'Resuming $unfinished unsynced change(s) saved before the app closed');
    }
    _repo.addLocalChangeListener((_) => scheduleSoon());
    _ticker = Timer.periodic(_period, (_) {
      if (_repo.pendingCount > 0 || _watch == null) syncNow();
    });
    onConnectivityChanged();
  }

  /// Called by the app whenever connectivity or the signed-in account changes.
  void onConnectivityChanged() {
    if (_isOnline()) {
      syncNow();
    } else {
      _stopWatching();
      _setPhase(SyncPhase.offline);
    }
  }

  void scheduleSoon() {
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, syncNow);
  }

  /// Runs a sync cycle. With [force], ops that are backing off are retried now.
  Future<void> syncNow({bool force = false}) async {
    if (_running) {
      _rerun = true;
      return;
    }
    if (!_isOnline()) {
      _setPhase(SyncPhase.offline);
      return;
    }
    final uid = _currentUid();
    if (uid == null) {
      _setPhase(SyncPhase.waitingForAccount);
      return;
    }

    _running = true;
    _setPhase(SyncPhase.syncing);
    try {
      await _handleAccountSwitch(uid);
      final pushErrors = await _pushAll(uid, force: force);
      await _pull(uid);
      _startWatching(uid);
      await _store.setLastSyncAt(DateTime.now());
      if (pushErrors == 0) {
        _lastError = null;
        _setPhase(SyncPhase.idle);
      } else {
        _setPhase(SyncPhase.error);
      }
    } on RemoteUnavailable catch (e) {
      _lastError = e.message;
      await _log(SyncLogKind.error, 'Sync failed: ${e.message}');
      _setPhase(_isOnline() ? SyncPhase.error : SyncPhase.offline);
    } catch (e) {
      _lastError = '$e';
      await _log(SyncLogKind.error, 'Unexpected sync error: $e');
      _setPhase(SyncPhase.error);
    } finally {
      _running = false;
      if (_rerun) {
        _rerun = false;
        scheduleSoon();
      }
    }
  }

  Future<void> _handleAccountSwitch(String uid) async {
    final previous = _store.syncedUid;
    if (previous == uid) return;
    if (previous != null) {
      await _log(SyncLogKind.info,
          'Signed in to a different account: local tasks will be merged into it');
      await _repo.resetSyncStateForNewAccount();
    }
    _stopWatching();
    await _store.setPullCursor(0);
    await _store.setSyncedUid(uid);
  }

  // ---------------------------------------------------------------- push

  /// Returns how many ops failed (and were rescheduled with backoff).
  Future<int> _pushAll(String uid, {required bool force}) async {
    final now = DateTime.now();
    var failures = 0;
    for (final rec in _repo.pendingQueue) {
      if (!force && !rec.pending!.isDue(now)) {
        failures++;
        continue;
      }
      try {
        await _pushOne(uid, rec.task.id, 0);
      } on RemoteUnavailable catch (e) {
        failures++;
        await _markFailed(rec.task.id, e.message);
        if (!_isOnline()) break; // no point hammering a dead connection
      }
    }
    return failures;
  }

  Future<void> _pushOne(String uid, String id, int depth) async {
    final rec = _repo.recordOf(id);
    if (rec == null || rec.pending == null) return;
    final op = rec.pending!;
    final sent = rec.task;

    final result = await _remote.push(
      uid: uid,
      task: sent,
      baseRev: rec.baseRev,
      opId: op.opId,
    );

    switch (result) {
      case PushApplied(:final newRev, :final replayed):
        await _repo.applySync([id], (_, cur) {
          if (cur == null || newRev <= cur.baseRev) return null;
          // If the user edited again while we were uploading, keep that newer
          // edit queued, now based on the revision we just created.
          final stillSame = cur.pending?.opId == op.opId;
          return cur.copyWith(
            base: sent,
            baseRev: newRev,
            clearPending: stillSame,
          );
        });
        await _log(
          SyncLogKind.push,
          replayed
              ? 'Already on server, recovered after an interrupted upload: "${sent.title}"'
              : '${_verb(sent, rec)} "${sent.title}" (rev $newRev)',
          taskId: id,
        );

      case PushConflict(:final remote):
        final again = await _resolveAgainst(remote, fromPush: true);
        if (again && depth < _maxConflictRetries) {
          await _pushOne(uid, id, depth + 1);
        }
    }
  }

  String _verb(Task t, LocalRecord r) {
    if (t.deleted) return 'Deleted';
    if (r.baseRev == 0) return 'Created';
    return 'Updated';
  }

  Future<void> _markFailed(String id, String error) async {
    PendingOp? updated;
    await _repo.applySync([id], (_, cur) {
      if (cur?.pending == null) return null;
      updated = cur!.pending!.failed(error, DateTime.now());
      return cur.copyWith(pending: updated);
    });
    if (updated != null) {
      final wait = updated!.nextAttemptAt!.difference(DateTime.now()).inSeconds;
      await _log(SyncLogKind.retry,
          'Upload failed (attempt ${updated!.attempts}), retrying in ${wait}s: $error',
          taskId: id);
    }
  }

  // ---------------------------------------------------------------- pull

  Future<void> _pull(String uid) async {
    final changes = await _remote.fetchChangedSince(uid, _store.pullCursor);
    await _applyRemote(changes);
  }

  void _startWatching(String uid) {
    if (_watch != null && _watchUid == uid) return;
    _stopWatching();
    _watchUid = uid;
    _watch = _remote.watchChangedSince(uid, _store.pullCursor).listen(
          (changes) => _applyRemote(changes),
          onError: (Object e) => _stopWatching(),
        );
  }

  void _stopWatching() {
    _watch?.cancel();
    _watch = null;
    _watchUid = null;
  }

  Future<void> _applyRemote(List<RemoteTask> changes) async {
    if (changes.isEmpty) return;
    var applied = 0;
    for (final rt in changes) {
      final cur = _repo.recordOf(rt.task.id);
      if (cur != null && rt.rev <= cur.baseRev) continue; // already have it
      if (cur != null && cur.isDirty) {
        await _resolveAgainst(rt, fromPush: false);
      } else {
        await _repo.applySync([rt.task.id], (_, now) {
          if (now != null && (rt.rev <= now.baseRev || now.isDirty)) return null;
          return LocalRecord(
            task: rt.task,
            base: rt.task,
            baseRev: rt.rev,
            lastConflictAt: now?.lastConflictAt,
          );
        });
      }
      applied++;
    }
    final newest = changes.map((c) => c.serverUpdatedAtMs).reduce(math.max);
    if (newest > _store.pullCursor) await _store.setPullCursor(newest);
    if (applied > 0) {
      await _log(SyncLogKind.pull, 'Received $applied change(s) from the server');
    }
  }

  // ------------------------------------------------------------ conflicts

  /// Merges a newer server version into a locally modified record.
  /// Returns true if the merged result still has to be pushed.
  Future<bool> _resolveAgainst(RemoteTask remote, {required bool fromPush}) async {
    MergeResult? merge;
    var needsPush = false;
    await _repo.applySync([remote.task.id], (_, cur) {
      if (cur == null || remote.rev <= cur.baseRev) return null;
      if (!cur.isDirty) {
        return LocalRecord(task: remote.task, base: remote.task, baseRev: remote.rev);
      }
      merge = mergeTasks(base: cur.base, local: cur.task, remote: remote.task);
      final merged = merge!.task;
      needsPush = !merged.sameContentAs(remote.task);
      return LocalRecord(
        task: needsPush ? merged : remote.task,
        base: remote.task,
        baseRev: remote.rev,
        pending: needsPush
            ? PendingOp(opId: _repo.newOpId(), queuedAt: cur.pending!.queuedAt)
            : null,
        lastConflictAt: merge!.hadTrueConflict ? DateTime.now() : cur.lastConflictAt,
      );
    });

    final m = merge;
    if (m != null) {
      final title = m.task.title;
      if (m.hadTrueConflict) {
        await _log(
          SyncLogKind.conflict,
          'Conflict on "$title": both devices changed ${m.conflictingFields.join(', ')}. '
          'Kept the most recent edit for those fields and merged the rest.',
          taskId: remote.task.id,
        );
      } else {
        await _log(
          SyncLogKind.conflict,
          'Merged "$title": this device and another changed different fields, both kept',
          taskId: remote.task.id,
        );
      }
    }
    return needsPush;
  }

  // ---------------------------------------------------------------- misc

  Future<void> _log(SyncLogKind kind, String message, {String? taskId}) async {
    await _store.addLog(
        SyncLogEntry(at: DateTime.now(), kind: kind, message: message, taskId: taskId));
    notifyListeners();
  }

  List<SyncLogEntry> get log => _store.logEntries();

  Future<void> clearLog() async {
    await _store.clearLog();
    notifyListeners();
  }

  void _setPhase(SyncPhase p) {
    if (_phase == p) return;
    _phase = p;
    notifyListeners();
  }

  /// Demo aid: change a task on the server as if another device had done it.
  Future<void> simulateRemoteEdit(Task t) async {
    final uid = _currentUid();
    if (uid == null || !_isOnline()) {
      throw RemoteUnavailable('Go online first: the edit is made on the server');
    }
    await _remote.simulateRemoteEdit(uid, t.id, (remote) {
      final now = DateTime.now();
      return remote.copyWith(
        title: '${remote.title} (edited on another device)',
        priority: Priority.high,
        tags: {...remote.tags, 'remote'}.toList(),
        updatedAt: now,
        lastModifiedBy: 'other-device',
      );
    });
    await _log(SyncLogKind.info, 'Simulated an edit from another device on "${t.title}"',
        taskId: t.id);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ticker?.cancel();
    _stopWatching();
    super.dispose();
  }
}
