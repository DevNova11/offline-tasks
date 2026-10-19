import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/task_repository.dart';
import '../models/sync_log_entry.dart';
import '../sync/connectivity_service.dart';
import '../sync/sync_engine.dart';
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
    final theme = Theme.of(context);
    final time = DateFormat.MMMd().add_jms();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync activity'),
        actions: [
          IconButton(
            tooltip: 'Clear history',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: log.isEmpty ? null : sync.clearLog,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            child: ListTile(
              leading: Icon(online ? Icons.cloud_done : Icons.cloud_off),
              title: Text(online ? 'Online' : 'Offline'),
              subtitle: Text(formatLastSync(sync.lastSyncAt)),
              trailing: FilledButton.tonal(
                onPressed: online && !sync.isSyncing
                    ? () => sync.syncNow(force: true)
                    : null,
                child: Text(sync.isSyncing ? 'Syncing…' : 'Sync now'),
              ),
            ),
          ),
          _Header('Waiting to upload (${queue.length})'),
          if (queue.isEmpty)
            const ListTile(
              leading: Icon(Icons.check_circle_outline),
              title: Text('Nothing pending. Everything is on the server.'),
            ),
          for (final r in queue)
            ListTile(
              dense: true,
              leading: Icon(
                r.pending!.attempts > 0 ? Icons.error_outline : Icons.schedule,
                color: r.pending!.attempts > 0 ? theme.colorScheme.error : null,
              ),
              title: Text(
                '${r.task.deleted ? 'Delete' : r.baseRev == 0 ? 'Create' : 'Update'}: ${r.task.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(r.pending!.attempts == 0
                  ? 'Queued ${time.format(r.pending!.queuedAt)}'
                  : 'Failed ${r.pending!.attempts}×: ${r.pending!.lastError}\n'
                      'Next try ${time.format(r.pending!.nextAttemptAt!)}'),
            ),
          _Header('History'),
          if (log.isEmpty)
            const ListTile(title: Text('No sync activity yet.')),
          for (final e in log)
            ListTile(
              dense: true,
              leading: Icon(_icon(e.kind), color: _color(e.kind, theme.colorScheme)),
              title: Text(e.message),
              subtitle: Text(time.format(e.at)),
            ),
        ],
      ),
    );
  }

  static IconData _icon(SyncLogKind k) => switch (k) {
        SyncLogKind.push => Icons.upload,
        SyncLogKind.pull => Icons.download,
        SyncLogKind.conflict => Icons.merge_type,
        SyncLogKind.retry => Icons.replay,
        SyncLogKind.error => Icons.error_outline,
        SyncLogKind.recovery => Icons.restore,
        SyncLogKind.info => Icons.info_outline,
      };

  static Color? _color(SyncLogKind k, ColorScheme s) => switch (k) {
        SyncLogKind.conflict => Colors.deepPurple,
        SyncLogKind.retry || SyncLogKind.error => s.error,
        SyncLogKind.recovery => Colors.teal,
        _ => null,
      };
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}
