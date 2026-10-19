import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/task_repository.dart';
import '../../models/local_record.dart';
import '../../models/task.dart';
import '../theme.dart';
import 'ios.dart';

/// One task row in Reminders style, drawn as part of an inset grouped list.
class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.record,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
    required this.onLongPress,
    this.dragHandle,
  });

  final LocalRecord record;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context) {
    final t = record.task;
    final repo = context.read<TaskRepository>();
    final radius = BorderRadius.vertical(
      top: isFirst ? const Radius.circular(12) : Radius.zero,
      bottom: isLast ? const Radius.circular(12) : Radius.zero,
    );
    final bg = resolve(context, CupertinoColors.secondarySystemGroupedBackground);

    final row = Container(
      decoration: BoxDecoration(color: bg, borderRadius: radius),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CompletionCircle(
                done: t.completed,
                color: priorityColor(t.priority),
                onTap: () => repo.setCompleted(t, !t.completed),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: _Content(task: t),
                ),
              ),
              _SyncBadge(record: record),
              ?dragHandle,
              const SizedBox(width: 6),
            ],
          ),
          if (!isLast)
            Container(
              margin: const EdgeInsets.only(left: 48),
              height: 0.5,
              color: resolve(context, CupertinoColors.separator),
            ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: radius,
        child: Dismissible(
          key: ValueKey('dismiss-${t.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            color: CupertinoColors.systemRed,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.trash, color: CupertinoColors.white, size: 20),
                SizedBox(width: 6),
                Text('Delete',
                    style: TextStyle(
                        color: CupertinoColors.white, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          onDismissed: (_) => deleteWithUndo(context, t),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            onLongPress: onLongPress,
            child: row,
          ),
        ),
      ),
    );
  }
}

void deleteWithUndo(BuildContext context, Task t) {
  final repo = context.read<TaskRepository>();
  repo.delete(t);
  showToast(
    context,
    'Deleted "${t.title}"',
    actionLabel: 'Undo',
    onAction: () => repo.restore(t),
  );
}

class _Content extends StatelessWidget {
  const _Content({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final t = task;
    final label = resolve(context, CupertinoColors.label);
    final secondary = resolve(context, CupertinoColors.secondaryLabel);
    final pColor = priorityColor(t.priority);

    final meta = <InlineSpan>[];
    void sep() {
      if (meta.isNotEmpty) meta.add(const TextSpan(text: '  '));
    }

    if (t.dueAt != null) {
      final overdue = t.isOverdue;
      meta.add(TextSpan(
        text: _formatDue(t.dueAt!),
        style: TextStyle(
          color: overdue ? resolve(context, CupertinoColors.systemRed) : secondary,
        ),
      ));
    }
    if (t.recurrence != Recurrence.none) {
      sep();
      meta.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Icon(CupertinoIcons.repeat, size: 12, color: secondary),
      ));
    }
    if (t.category != null) {
      sep();
      meta.add(TextSpan(text: t.category!, style: TextStyle(color: secondary)));
    }
    for (final tag in t.tags) {
      sep();
      meta.add(TextSpan(
        text: '#$tag',
        style: TextStyle(color: resolve(context, CupertinoColors.systemBlue)),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(children: [
            if (!t.completed && t.priority != Priority.medium)
              TextSpan(
                text: '${priorityMarks(t.priority)} ',
                style: TextStyle(color: pColor, fontWeight: FontWeight.w600),
              ),
            TextSpan(text: t.title),
          ]),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 17,
            letterSpacing: -0.4,
            color: t.completed ? secondary : label,
            decoration: t.completed ? TextDecoration.lineThrough : null,
            decorationColor: secondary,
          ),
        ),
        if (t.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              t.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, color: secondary),
            ),
          ),
        if (meta.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text.rich(TextSpan(children: meta),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14)),
          ),
      ],
    );
  }

  static String _formatDue(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final time = DateFormat.jm().format(d);
    final diff = day.difference(today).inDays;
    if (diff == 0) return 'Today, $time';
    if (diff == 1) return 'Tomorrow, $time';
    if (diff == -1) return 'Yesterday, $time';
    return '${DateFormat('d/M/yy').format(d)}, $time';
  }
}

/// Per-task sync state: synced, waiting to upload, failing, or auto-merged.
class _SyncBadge extends StatelessWidget {
  const _SyncBadge({required this.record});
  final LocalRecord record;

  @override
  Widget build(BuildContext context) {
    final p = record.pending;
    final recentConflict = record.lastConflictAt != null &&
        DateTime.now().difference(record.lastConflictAt!).inMinutes < 10;

    final (IconData icon, Color color) = p != null && p.attempts > 0
        ? (CupertinoIcons.exclamationmark_circle, CupertinoColors.systemRed)
        : p != null || record.baseRev == 0
            ? (CupertinoIcons.cloud_upload, CupertinoColors.systemBlue)
            : recentConflict
                ? (CupertinoIcons.arrow_merge, CupertinoColors.systemPurple)
                : (CupertinoIcons.checkmark_alt_circle, CupertinoColors.systemGrey3);

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 13, 6, 0),
      child: Icon(icon, size: 17, color: resolve(context, color)),
    );
  }
}
