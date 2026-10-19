import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/task_repository.dart';
import '../../sync/connectivity_service.dart';
import '../../sync/sync_engine.dart';

/// App-bar button: shows online/offline/syncing at a glance; tap to sync now.
class SyncStatusButton extends StatelessWidget {
  const SyncStatusButton({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncEngine>();
    final online = context.watch<ConnectivityService>().isOnline;
    final pending = context.select<TaskRepository, int>((r) => r.pendingCount);
    final scheme = Theme.of(context).colorScheme;

    final (IconData icon, Color color, String label) = !online
        ? (Icons.cloud_off, scheme.error, 'Offline')
        : switch (sync.phase) {
            SyncPhase.syncing => (Icons.sync, scheme.primary, 'Syncing'),
            SyncPhase.error => (Icons.sync_problem, scheme.error, 'Sync error'),
            SyncPhase.waitingForAccount =>
              (Icons.cloud_queue, scheme.outline, 'Connecting'),
            _ => pending > 0
                ? (Icons.cloud_upload_outlined, scheme.primary, 'Online')
                : (Icons.cloud_done, Colors.green, 'Online'),
          };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: online ? 'Sync now' : 'Offline: changes are saved on this device',
        child: ActionChip(
          avatar: sync.isSyncing
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: color),
                )
              : Icon(icon, size: 18, color: color),
          label: Text(pending > 0 ? '$label · $pending' : label),
          onPressed: online
              ? () => context.read<SyncEngine>().syncNow(force: true)
              : null,
        ),
      ),
    );
  }
}

/// Banner under the app bar explaining offline / error states.
class ConnectivityBanner extends StatelessWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectivityService>();
    final sync = context.watch<SyncEngine>();
    final pending = context.select<TaskRepository, int>((r) => r.pendingCount);
    final scheme = Theme.of(context).colorScheme;

    Widget bar(Color bg, Color fg, IconData icon, String text, {Widget? action}) =>
        Material(
          color: bg,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(text,
                        style: TextStyle(color: fg, fontSize: 13))),
                ?action,
              ],
            ),
          ),
        );

    if (!conn.isOnline) {
      final why = conn.forcedOffline ? 'Offline mode is on' : 'You are offline';
      return bar(
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        Icons.cloud_off,
        pending == 0
            ? '$why. Everything still works; changes are saved on this device.'
            : '$why. $pending change(s) saved on this device will sync when you reconnect.',
        action: conn.forcedOffline
            ? TextButton(
                onPressed: () => conn.setForcedOffline(false),
                child: const Text('Go online'),
              )
            : null,
      );
    }
    if (sync.phase == SyncPhase.error) {
      return bar(
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.sync_problem,
        'Sync problem: ${sync.lastError ?? 'some changes could not be uploaded'}. '
        'Will retry automatically.',
        action: TextButton(
          onPressed: () => sync.syncNow(force: true),
          child: const Text('Retry'),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

String formatLastSync(DateTime? t) {
  if (t == null) return 'Never synced';
  final diff = DateTime.now().difference(t);
  if (diff.inSeconds < 60) return 'Synced just now';
  if (diff.inMinutes < 60) return 'Synced ${diff.inMinutes} min ago';
  return 'Synced ${DateFormat.MMMd().add_jm().format(t)}';
}
