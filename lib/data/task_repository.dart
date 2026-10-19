import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/lock.dart';
import '../models/local_record.dart';
import '../models/task.dart';
import 'local_store.dart';

/// All task reads and writes go through here.
///
/// Every change is written to disk (task + queued sync op, one atomic write)
/// and then the in-memory list is updated and listeners are notified, so the
/// UI reacts instantly whether or not there is a network.
class TaskRepository extends ChangeNotifier {
  TaskRepository(this._store) {
    for (final r in _store.allRecords()) {
      _records[r.task.id] = r;
    }
  }

  final LocalStore _store;
  final _records = <String, LocalRecord>{};
  static const _uuid = Uuid();

  /// Serialises every read-modify-write, so a user edit can never be lost to
  /// a sync result computed from an older version of the same record.
  final _lock = Lock();

  /// Called after every local change (sync engine kick, notifications).
  final _localChangeListeners = <void Function(Task)>[];
  void addLocalChangeListener(void Function(Task) l) => _localChangeListeners.add(l);

  /// Called whenever a task changes for any reason, local or remote.
  final _taskChangeListeners = <void Function(Task)>[];
  void addTaskChangeListener(void Function(Task) l) => _taskChangeListeners.add(l);

  String get deviceId => _store.deviceId;

  // ---- reads ----

  /// Visible (non-deleted) tasks.
  List<Task> get tasks =>
      _records.values.where((r) => !r.task.deleted).map((r) => r.task).toList();

  LocalRecord? recordOf(String id) => _records[id];
  Iterable<LocalRecord> get records => _records.values;

  List<LocalRecord> get pendingQueue =>
      _records.values.where((r) => r.isDirty).toList()
        ..sort((a, b) => a.pending!.queuedAt.compareTo(b.pending!.queuedAt));

  int get pendingCount => _records.values.where((r) => r.isDirty).length;

  Set<String> get allTags => {for (final t in tasks) ...t.tags};
  Set<String> get allCategories =>
      {for (final t in tasks) if (t.category != null && t.category!.isNotEmpty) t.category!};

  // ---- writes ----

  Future<Task> create({
    required String title,
    String description = '',
    Priority priority = Priority.medium,
    DateTime? dueAt,
    String? category,
    List<String> tags = const [],
    Recurrence recurrence = Recurrence.none,
    String? id,
  }) async {
    final now = DateTime.now();
    final minOrder = tasks.isEmpty
        ? 0.0
        : tasks.map((t) => t.sortOrder).reduce((a, b) => a < b ? a : b);
    final task = Task(
      id: id ?? _uuid.v4(),
      title: title.trim(),
      description: description.trim(),
      priority: priority,
      dueAt: dueAt,
      category: (category?.trim().isEmpty ?? true) ? null : category!.trim(),
      tags: tags,
      recurrence: recurrence,
      sortOrder: minOrder - 1, // new tasks go to the top
      createdAt: now,
      updatedAt: now,
      lastModifiedBy: deviceId,
    );
    await _commitLocal(task);
    return task;
  }

  Future<void> update(Task task) => _commitLocal(task);

  Future<void> setCompleted(Task task, bool completed) async {
    await _commitLocal(task.copyWith(
      completed: completed,
      completedAt: completed ? DateTime.now() : null,
    ));
    if (completed && task.recurrence != Recurrence.none) {
      await _spawnNextOccurrence(task);
    }
  }

  /// Soft delete (tombstone) so the deletion reaches the server.
  Future<void> delete(Task task) => _commitLocal(task.copyWith(deleted: true));

  Future<void> restore(Task task) => _commitLocal(task.copyWith(deleted: false));

  /// Moves [task] between two neighbours in manual order.
  Future<void> moveBetween(Task task, Task? before, Task? after) {
    final double order;
    if (before == null && after == null) {
      order = 0;
    } else if (before == null) {
      order = after!.sortOrder - 1;
    } else if (after == null) {
      order = before.sortOrder + 1;
    } else {
      order = (before.sortOrder + after.sortOrder) / 2;
    }
    return _commitLocal(task.copyWith(sortOrder: order));
  }

  /// The next occurrence gets a deterministic id derived from the parent and
  /// its due date, so if two offline devices both complete the same recurring
  /// task they create the *same* follow-up task instead of a duplicate.
  Future<void> _spawnNextOccurrence(Task t) async {
    final from = t.dueAt ?? DateTime.now();
    var next = _advance(from, t.recurrence);
    while (next.isBefore(DateTime.now())) {
      next = _advance(next, t.recurrence);
    }
    final id = _uuid.v5(Namespace.url.value, '${t.id}@${next.millisecondsSinceEpoch}');
    if (_records.containsKey(id)) return;
    await create(
      id: id,
      title: t.title,
      description: t.description,
      priority: t.priority,
      dueAt: t.dueAt == null ? null : next,
      category: t.category,
      tags: t.tags,
      recurrence: t.recurrence,
    );
  }

  static DateTime _advance(DateTime d, Recurrence r) => switch (r) {
        Recurrence.daily => d.add(const Duration(days: 1)),
        Recurrence.weekly => d.add(const Duration(days: 7)),
        Recurrence.monthly => DateTime(d.year, d.month + 1, d.day, d.hour, d.minute),
        Recurrence.none => d,
      };

  Future<void> _commitLocal(Task edited) => _lock.run(() async {
        final now = DateTime.now();
        final task = edited.copyWith(updatedAt: now, lastModifiedBy: deviceId);
        final existing = _records[task.id];
        final record = (existing ?? LocalRecord(task: task)).copyWith(
          task: task,
          // A fresh op id per edit; keep the original queue position.
          pending: PendingOp(
            opId: _uuid.v4(),
            queuedAt: existing?.pending?.queuedAt ?? now,
          ),
        );
        await _store.putRecord(record); // persist first: survives a crash
        _records[task.id] = record;
        notifyListeners();
        for (final l in _localChangeListeners) {
          l(task);
        }
        for (final l in _taskChangeListeners) {
          l(task);
        }
      });

  // ---- used by the sync engine ----

  /// Atomically updates records on behalf of the sync engine. [fn] receives
  /// the record as it is *now* (under the lock) and returns the new record,
  /// or null to leave it untouched.
  Future<void> applySync(
    Iterable<String> ids,
    LocalRecord? Function(String id, LocalRecord? current) fn,
  ) =>
      _lock.run(() async {
        final changed = <LocalRecord>[];
        for (final id in ids) {
          final next = fn(id, _records[id]);
          if (next != null) changed.add(next);
        }
        if (changed.isEmpty) return;
        await _store.putRecords(changed);
        for (final r in changed) {
          final before = _records[r.task.id];
          _records[r.task.id] = r;
          if (before == null || !before.task.sameContentAs(r.task)) {
            for (final l in _taskChangeListeners) {
              l(r.task);
            }
          }
        }
        notifyListeners();
      });

  /// After switching accounts, local data has no server history in the new
  /// account: requeue everything so it is uploaded (and merged) there.
  Future<void> resetSyncStateForNewAccount() {
    final now = DateTime.now();
    return applySync(
      _records.keys.toList(),
      (_, r) => LocalRecord(
        task: r!.task,
        pending: r.pending ?? PendingOp(opId: _uuid.v4(), queuedAt: now),
      ),
    );
  }

  String newOpId() => _uuid.v4();
}
