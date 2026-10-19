import 'dart:math' as math;

import 'task.dart';

/// A queued change waiting to be pushed to the server.
///
/// It lives inside the same [LocalRecord] as the task it belongs to, so the
/// edit and its queue entry are persisted in a single atomic write: there is
/// no moment where the task has changed but the change is not queued.
class PendingOp {
  PendingOp({
    required this.opId,
    required this.queuedAt,
    this.attempts = 0,
    this.nextAttemptAt,
    this.lastError,
  });

  /// Idempotency key. Written to the server with the change, so a retry of a
  /// push that actually succeeded (e.g. the app died before hearing back) is
  /// recognised instead of applied twice.
  final String opId;
  final DateTime queuedAt;
  final int attempts;
  final DateTime? nextAttemptAt;
  final String? lastError;

  PendingOp failed(String error, DateTime now) {
    final n = attempts + 1;
    // Exponential backoff: 2s, 4s, 8s ... capped at 5 minutes.
    final delay = Duration(seconds: math.min(300, 1 << math.min(n, 9)));
    return PendingOp(
      opId: opId,
      queuedAt: queuedAt,
      attempts: n,
      nextAttemptAt: now.add(delay),
      lastError: error,
    );
  }

  bool isDue(DateTime now) =>
      nextAttemptAt == null || !nextAttemptAt!.isAfter(now);

  Map<String, dynamic> toJson() => {
        'opId': opId,
        'queuedAt': queuedAt.millisecondsSinceEpoch,
        'attempts': attempts,
        'nextAttemptAt': nextAttemptAt?.millisecondsSinceEpoch,
        'lastError': lastError,
      };

  factory PendingOp.fromJson(Map<String, dynamic> j) => PendingOp(
        opId: j['opId'] as String,
        queuedAt: DateTime.fromMillisecondsSinceEpoch(j['queuedAt'] as int),
        attempts: (j['attempts'] as int?) ?? 0,
        nextAttemptAt: j['nextAttemptAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(j['nextAttemptAt'] as int),
        lastError: j['lastError'] as String?,
      );
}

/// Everything the device knows about one task.
class LocalRecord {
  LocalRecord({
    required this.task,
    this.base,
    this.baseRev = 0,
    this.pending,
    this.lastConflictAt,
  });

  /// Current local state, shown in the UI.
  final Task task;

  /// Last state confirmed by the server: the common ancestor for three-way
  /// merges. Null if the task has never been synced.
  final Task? base;

  /// Server revision of [base]. A push only succeeds if the server is still
  /// at this revision (optimistic concurrency).
  final int baseRev;

  /// Non-null while there is an unsynced local change.
  final PendingOp? pending;

  /// Set when a conflict was auto-resolved, so the UI can flag the task.
  final DateTime? lastConflictAt;

  bool get isDirty => pending != null;

  LocalRecord copyWith({
    Task? task,
    Task? base,
    int? baseRev,
    PendingOp? pending,
    bool clearPending = false,
    DateTime? lastConflictAt,
  }) =>
      LocalRecord(
        task: task ?? this.task,
        base: base ?? this.base,
        baseRev: baseRev ?? this.baseRev,
        pending: clearPending ? null : (pending ?? this.pending),
        lastConflictAt: lastConflictAt ?? this.lastConflictAt,
      );

  Map<String, dynamic> toJson() => {
        'task': task.toJson(),
        'base': base?.toJson(),
        'baseRev': baseRev,
        'pending': pending?.toJson(),
        'lastConflictAt': lastConflictAt?.millisecondsSinceEpoch,
      };

  factory LocalRecord.fromJson(Map<String, dynamic> j) => LocalRecord(
        task: Task.fromJson((j['task'] as Map).cast<String, dynamic>()),
        base: j['base'] == null
            ? null
            : Task.fromJson((j['base'] as Map).cast<String, dynamic>()),
        baseRev: (j['baseRev'] as int?) ?? 0,
        pending: j['pending'] == null
            ? null
            : PendingOp.fromJson((j['pending'] as Map).cast<String, dynamic>()),
        lastConflictAt: j['lastConflictAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(j['lastConflictAt'] as int),
      );
}
