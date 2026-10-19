import '../models/task.dart';

/// A task as stored on the server, with its concurrency metadata.
class RemoteTask {
  RemoteTask({
    required this.task,
    required this.rev,
    required this.serverUpdatedAtMs,
    this.lastOpId,
  });

  final Task task;

  /// Monotonic server revision, incremented on every accepted write.
  final int rev;
  final int serverUpdatedAtMs;

  /// Idempotency key of the op that produced this revision.
  final String? lastOpId;
}

sealed class PushResult {}

class PushApplied extends PushResult {
  PushApplied(this.newRev, {this.replayed = false});
  final int newRev;

  /// The server already had this exact op (an earlier attempt succeeded but
  /// the app never got the answer). Nothing was written twice.
  final bool replayed;
}

class PushConflict extends PushResult {
  PushConflict(this.remote);

  /// What the server has now; somebody else wrote since our base revision.
  final RemoteTask remote;
}

/// The remote database. Abstract so the sync engine can be tested against an
/// in-memory implementation.
abstract class RemoteTaskStore {
  /// Conditionally writes [task]: succeeds only if the server is still at
  /// [baseRev] (0 = must not exist yet). Implementations must be atomic.
  Future<PushResult> push({
    required String uid,
    required Task task,
    required int baseRev,
    required String opId,
  });

  /// Every task whose server timestamp is >= [cursorMs].
  Future<List<RemoteTask>> fetchChangedSince(String uid, int cursorMs);

  /// Live updates for tasks changed at or after [cursorMs].
  Stream<List<RemoteTask>> watchChangedSince(String uid, int cursorMs);

  /// Demo/testing aid: edits the server copy as if another device did it.
  Future<void> simulateRemoteEdit(
    String uid,
    String taskId,
    Task Function(Task) edit,
  );
}

class RemoteUnavailable implements Exception {
  RemoteUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}
