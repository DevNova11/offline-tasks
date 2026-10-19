import 'package:flutter/foundation.dart';

import '../models/task.dart';

class MergeResult {
  MergeResult(this.task, this.conflictingFields);

  final Task task;

  /// Fields both sides changed to different values. Empty means the two
  /// edits touched different fields and merged cleanly.
  final List<String> conflictingFields;

  bool get hadTrueConflict => conflictingFields.isNotEmpty;
}

const _mergeableFields = [
  'title',
  'description',
  'priority',
  'dueAt',
  'category',
  'tags',
  'completed',
  'recurrence',
  'sortOrder',
  'deleted',
];

bool _eq(Object? a, Object? b) {
  if (a is List && b is List) return listEquals(a, b);
  return a == b;
}

/// Three-way merge of a task edited both locally and on the server.
///
/// [base] is the last server state both sides started from. For every field:
/// * changed on one side only: that side's value wins, so edits to different
///   fields never overwrite each other;
/// * changed on both sides: tags are set-merged (additions and removals from
///   both sides are kept); any other field goes to the newer edit
///   (last-writer-wins on `updatedAt`, device id as a deterministic tie-break,
///   so every device resolves the same conflict the same way);
/// * delete vs edit: the deletion wins unless the other side edited the task
///   after it was deleted, in which case the task is restored.
MergeResult mergeTasks({
  required Task? base,
  required Task local,
  required Task remote,
}) {
  final localNewer = local.updatedAt.isAfter(remote.updatedAt) ||
      (local.updatedAt == remote.updatedAt &&
          local.lastModifiedBy.compareTo(remote.lastModifiedBy) > 0);

  final b = base?.toJson();
  final l = local.toJson();
  final r = remote.toJson();
  final out = Map<String, dynamic>.from(localNewer ? l : r);
  final conflicts = <String>[];

  for (final f in _mergeableFields) {
    final lv = l[f], rv = r[f];
    if (_eq(lv, rv)) {
      out[f] = lv;
    } else if (b != null && _eq(lv, b[f])) {
      out[f] = rv; // only the server changed it
    } else if (b != null && _eq(rv, b[f])) {
      out[f] = lv; // only we changed it
    } else if (f == 'tags') {
      out[f] = _mergeTags(
        base: base?.tags ?? const [],
        local: local.tags,
        remote: remote.tags,
      );
    } else {
      out[f] = localNewer ? lv : rv;
      conflicts.add(f);
    }
  }

  // completedAt follows whichever side's `completed` value survived.
  out['completedAt'] = out['completed'] == true
      ? (local.completed ? l['completedAt'] : r['completedAt'])
      : null;

  // Delete vs. edit: an edit made after the deletion resurrects the task.
  if (out['deleted'] == true && local.deleted != remote.deleted) {
    final deleter = local.deleted ? local : remote;
    final editor = local.deleted ? remote : local;
    final editorChangedContent = base == null ||
        !editor.copyWith(deleted: false).sameContentAs(base.copyWith(deleted: false));
    if (editorChangedContent && editor.updatedAt.isAfter(deleter.updatedAt)) {
      out['deleted'] = false;
      conflicts.add('deleted');
    }
  }

  out['updatedAt'] = (localNewer ? local.updatedAt : remote.updatedAt)
      .millisecondsSinceEpoch;
  return MergeResult(Task.fromJson(out), conflicts);
}

List<String> _mergeTags({
  required List<String> base,
  required List<String> local,
  required List<String> remote,
}) {
  final b = base.toSet();
  final removed = b.difference(local.toSet()).union(b.difference(remote.toSet()));
  final result = <String>[];
  for (final t in [...local, ...remote]) {
    if (!removed.contains(t) && !result.contains(t)) result.add(t);
  }
  return result;
}
