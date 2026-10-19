import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/task_repository.dart';
import '../models/sync_log_entry.dart';
import '../sync/connectivity_service.dart';
import '../sync/sync_engine.dart';
import 'theme.dart';
import 'widgets/ios.dart';
import 'widgets/sync_status.dart';

/// The outbox (what is still waiting to upload) and the sync history.
class SyncActivityScreen extends StatelessWidget {
  const SyncActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncEngine>();
    final repo = context.watch<TaskRepository>();
    final online = context.watch<ConnectivityService>().isOnline;
    final queue = repo.pendingQueue;
    final log = sync.log;
    final time = DateFormat('d MMM, h:mm:ss a');

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Sync Activity'),
        previousPageTitle: 'Tasks',
        trailing: log.isEmpty
            ? null
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _confirmClear(context, sync),
                child: const Text('Clear'),
              ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            CupertinoListSection.insetGrouped(
              children: [
                CupertinoListTile(
                  leading: Icon(
                    online ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.wifi_slash,
                    color: resolve(context,
                        online ? CupertinoColors.systemGreen : CupertinoColors.systemOrange),
                  ),
                  title: Text(online ? 'Online' : 'Offline'),
                  subtitle: Text(formatLastSync(sync.lastSyncAt)),
                  trailing: sync.isSyncing
                      ? const CupertinoActivityIndicator()
                      : CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: online ? () => sync.syncNow(force: true) : null,
                          child: const Text('Sync Now'),
                        ),
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: SectionHeader('Waiting to Upload (${queue.length})'),
              children: [
                if (queue.isEmpty)
                  CupertinoListTile(
                    leading: Icon(CupertinoIcons.checkmark_circle,
                        color: resolve(context, CupertinoColors.systemGreen)),
                    title: const Text('Everything is on the server'),
                  ),
                for (final r in queue)
                  CupertinoListTile(
                    leading: Icon(
                      r.pending!.attempts > 0
                          ? CupertinoIcons.exclamationmark_circle
                          : CupertinoIcons.clock,
                      color: resolve(
                          context,
                          r.pending!.attempts > 0
                              ? CupertinoColors.systemRed
                              : CupertinoColors.systemBlue),
                    ),
                    title: Text(
                      '${r.task.deleted ? 'Delete' : r.baseRev == 0 ? 'Create' : 'Update'}: ${r.task.title}',
                    ),
                    subtitle: Text(
                      r.pending!.attempts == 0
                          ? 'Queued ${time.format(r.pending!.queuedAt)}'
                          : 'Failed ${r.pending!.attempts}× · next try '
                              '${time.format(r.pending!.nextAttemptAt!)}',
                    ),
                  ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const SectionHeader('History'),
              children: [
                if (log.isEmpty)
                  const CupertinoListTile(title: Text('No sync activity yet')),
                for (final e in log)
                  CupertinoListTile(
                    leading: Icon(_icon(e.kind), color: resolve(context, _color(e.kind))),
                    title: Text(e.message, maxLines: 3),
                    subtitle: Text(time.format(e.at)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, SyncEngine sync) async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Clear History?'),
        content: const Text('Queued changes are not affected.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true) await sync.clearLog();
  }

  static IconData _icon(SyncLogKind k) => switch (k) {
        SyncLogKind.push => CupertinoIcons.arrow_up_circle,
        SyncLogKind.pull => CupertinoIcons.arrow_down_circle,
        SyncLogKind.conflict => CupertinoIcons.arrow_merge,
        SyncLogKind.retry => CupertinoIcons.arrow_clockwise,
        SyncLogKind.error => CupertinoIcons.exclamationmark_triangle,
        SyncLogKind.recovery => CupertinoIcons.arrow_counterclockwise_circle,
        SyncLogKind.info => CupertinoIcons.info_circle,
      };

  static Color _color(SyncLogKind k) => switch (k) {
        SyncLogKind.push => CupertinoColors.systemBlue,
        SyncLogKind.pull => CupertinoColors.systemTeal,
        SyncLogKind.conflict => CupertinoColors.systemPurple,
        SyncLogKind.retry || SyncLogKind.error => CupertinoColors.systemRed,
        SyncLogKind.recovery => CupertinoColors.systemGreen,
        SyncLogKind.info => CupertinoColors.systemGrey,
      };
}
