import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/task.dart';
import 'remote_store.dart';

/// Firestore-backed remote: `users/{uid}/tasks/{taskId}`.
///
/// Firestore's own offline cache is switched off in main.dart, so every read
/// and write here really talks to the server and the app's own sync engine is
/// the only thing deciding what is synced.
class FirestoreRemoteStore implements RemoteTaskStore {
  FirestoreRemoteStore(this._db);

  final FirebaseFirestore _db;
  static const _timeout = Duration(seconds: 15);

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('tasks');

  @override
  Future<PushResult> push({
    required String uid,
    required Task task,
    required int baseRev,
    required String opId,
  }) {
    final ref = _col(uid).doc(task.id);
    return _guard(() => _db.runTransaction<PushResult>((tx) async {
          final snap = await tx.get(ref);
          final data = snap.data();
          final remoteRev = (data?['rev'] as num?)?.toInt() ?? 0;

          if (data != null && data['lastOpId'] == opId) {
            return PushApplied(remoteRev, replayed: true);
          }
          if (remoteRev != baseRev) {
            return PushConflict(_fromDoc(data!));
          }
          tx.set(ref, {
            ...task.toJson(),
            'rev': baseRev + 1,
            'lastOpId': opId,
            'serverUpdatedAt': FieldValue.serverTimestamp(),
          });
          return PushApplied(baseRev + 1);
        }));
  }

  @override
  Future<List<RemoteTask>> fetchChangedSince(String uid, int cursorMs) =>
      _guard(() async {
        final q = await _query(uid, cursorMs).get();
        return q.docs.map((d) => _fromDoc(d.data())).toList();
      });

  @override
  Stream<List<RemoteTask>> watchChangedSince(String uid, int cursorMs) =>
      _query(uid, cursorMs).snapshots().map((s) => s.docChanges
          .where((c) => c.type != DocumentChangeType.removed)
          .map((c) => _fromDoc(c.doc.data()!))
          .toList());

  @override
  Future<void> simulateRemoteEdit(
    String uid,
    String taskId,
    Task Function(Task) edit,
  ) {
    final ref = _col(uid).doc(taskId);
    return _guard(() => _db.runTransaction((tx) async {
          final snap = await tx.get(ref);
          if (!snap.exists) throw RemoteUnavailable('Task is not on the server yet');
          final current = _fromDoc(snap.data()!);
          tx.set(ref, {
            ...edit(current.task).toJson(),
            'rev': current.rev + 1,
            'lastOpId': 'simulated-${DateTime.now().microsecondsSinceEpoch}',
            'serverUpdatedAt': FieldValue.serverTimestamp(),
          });
        }));
  }

  Query<Map<String, dynamic>> _query(String uid, int cursorMs) => _col(uid)
      .where('serverUpdatedAt',
          isGreaterThanOrEqualTo: Timestamp.fromMillisecondsSinceEpoch(cursorMs))
      .orderBy('serverUpdatedAt');

  RemoteTask _fromDoc(Map<String, dynamic> d) {
    final ts = d['serverUpdatedAt'];
    return RemoteTask(
      task: Task.fromJson(d),
      rev: (d['rev'] as num?)?.toInt() ?? 0,
      serverUpdatedAtMs: ts is Timestamp
          ? ts.millisecondsSinceEpoch
          : DateTime.now().millisecondsSinceEpoch,
      lastOpId: d['lastOpId'] as String?,
    );
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body().timeout(_timeout);
    } on TimeoutException {
      throw RemoteUnavailable('Server did not respond in time');
    } on FirebaseException catch (e) {
      throw RemoteUnavailable('${e.code}: ${e.message ?? ''}'.trim());
    }
  }
}
