import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/task_repository.dart';
import '../../models/local_record.dart';
import '../../models/task.dart';
import '../theme.dart';

class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.record,
    required this.onTap,
    required this.onLongPress,
    this.dragHandle,
  });

  final LocalRecord record;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context) {
    final t = record.task;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final repo = context.read<TaskRepository>();

    return Dismissible(
      key: ValueKey('dismiss-${t.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: scheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline, color: scheme.onError),
      ),
      onDismissed: (_) => deleteWithUndo(context, t),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: priorityColor(t.priority, scheme), width: 4),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
            child: Row(
              children: [
                Checkbox(
                  value: t.completed,
                  onChanged: (v) => repo.setCompleted(t, v ?? false),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          decoration: t.completed ? TextDecoration.lineThrough : null,
                          color: t.completed ? scheme.outline : null,
                        ),
                      ),
                      if (t.description.isNotEmpty)
                        Text(
                          t.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      _MetaRow(task: t),
                    ],
                  ),
                ),
                _SyncBadge(record: record),
                ?dragHandle,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void deleteWithUndo(BuildContext context, Task t) {
  final repo = context.read<TaskRepository>();
  repo.delete(t);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text('Deleted "${t.title}"'),
      action: SnackBarAction(label: 'Undo', onPressed: () => repo.restore(t)),
    ));
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.labelSmall;
    final items = <Widget>[];

    if (task.dueAt != null) {
      final overdue = task.isOverdue;
      items.add(Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(overdue ? Icons.warning_amber : Icons.schedule,
            size: 14, color: overdue ? scheme.error : scheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(_formatDue(task.dueAt!),
            style: small?.copyWith(
                color: overdue ? scheme.error : scheme.onSurfaceVariant,
                fontWeight: overdue ? FontWeight.bold : null)),
      ]));
    }
    if (task.recurrence != Recurrence.none) {
      items.add(Icon(Icons.repeat, size: 14, color: scheme.onSurfaceVariant));
    }
    if (task.category != null) {
      items.add(Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.folder_outlined, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(task.category!, style: small?.copyWith(color: scheme.onSurfaceVariant)),
      ]));
    }
    for (final tag in task.tags) {
      items.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('#$tag',
            style: small?.copyWith(color: scheme.onSecondaryContainer)),
      ));
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(spacing: 8, runSpacing: 4, children: items),
    );
  }

  static String _formatDue(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final time = DateFormat.jm().format(d);
    final diff = day.difference(today).inDays;
    if (diff == 0) return 'Today $time';
    if (diff == 1) return 'Tomorrow $time';
    if (diff == -1) return 'Yesterday $time';
    return '${DateFormat.MMMd().format(d)} $time';
  }
}

/// Per-task sync state: synced, waiting to upload, failing, or auto-merged.
class _SyncBadge extends StatelessWidget {
  const _SyncBadge({required this.record});
  final LocalRecord record;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = record.pending;
    final recentConflict = record.lastConflictAt != null &&
        DateTime.now().difference(record.lastConflictAt!).inMinutes < 10;

    final (IconData icon, Color color, String tip) = p != null && p.attempts > 0
        ? (Icons.cloud_sync, scheme.error,
            'Upload failed ${p.attempts}×, will retry: ${p.lastError}')
        : p != null
            ? (Icons.cloud_upload_outlined, scheme.primary, 'Waiting to sync')
            : recentConflict
                ? (Icons.merge_type, Colors.deepPurple, 'Conflict auto-resolved')
                : record.baseRev > 0
                    ? (Icons.cloud_done_outlined, scheme.outlineVariant, 'Synced')
                    : (Icons.cloud_upload_outlined, scheme.primary, 'Not synced yet');

    return Tooltip(
      message: tip,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}
