import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/task_repository.dart';
import '../../sync/connectivity_service.dart';
import '../../sync/sync_engine.dart';
import '../theme.dart';

/// Nav-bar status capsule: online / offline / syncing, plus pending count.
/// Tap to sync now.
class SyncStatusPill extends StatelessWidget {
  const SyncStatusPill({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncEngine>();
    final online = context.watch<ConnectivityService>().isOnline;
    final pending = context.select<TaskRepository, int>((r) => r.pendingCount);

    final (IconData icon, Color color, String label) = !online
        ? (CupertinoIcons.wifi_slash, CupertinoColors.systemOrange, 'Offline')
        : switch (sync.phase) {
            SyncPhase.syncing =>
              (CupertinoIcons.arrow_2_circlepath, CupertinoColors.systemBlue, 'Syncing'),
            SyncPhase.error => (CupertinoIcons.exclamationmark_circle,
                CupertinoColors.systemRed, 'Retrying'),
            SyncPhase.waitingForAccount =>
              (CupertinoIcons.cloud, CupertinoColors.systemGrey, 'Connecting'),
            _ => pending > 0
                ? (CupertinoIcons.cloud_upload, CupertinoColors.systemBlue, 'Online')
                : (CupertinoIcons.checkmark_alt_circle, CupertinoColors.systemGreen, 'Synced'),
          };
    final c = resolve(context, color);

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(0, 0),
      onPressed: online ? () => sync.syncNow(force: true) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            sync.isSyncing
                ? CupertinoActivityIndicator(radius: 6, color: c)
                : Icon(icon, size: 15, color: c),
            const SizedBox(width: 5),
            Text(
              pending > 0 ? '$label · $pending' : label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c),
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner explaining offline / sync-error states. Empty when all is well.
class ConnectivityBanner extends StatelessWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectivityService>();
    final sync = context.watch<SyncEngine>();
    final pending = context.select<TaskRepository, int>((r) => r.pendingCount);

    Widget card(Color tint, IconData icon, String title, String text,
            {String? action, VoidCallback? onAction}) =>
        Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            color: resolve(context, CupertinoColors.secondarySystemGroupedBackground),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 18, color: CupertinoColors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(text, style: AppText.secondary(context)),
                  ],
                ),
              ),
              if (action != null)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  onPressed: onAction,
                  child: Text(action, style: const TextStyle(fontSize: 15)),
                ),
            ],
          ),
        );

    if (!conn.isOnline) {
      return card(
        CupertinoColors.systemOrange,
        CupertinoIcons.wifi_slash,
        conn.forcedOffline ? 'Offline Mode' : 'No Connection',
        pending == 0
            ? 'Everything still works. Changes are saved on this device.'
            : '$pending change${pending == 1 ? '' : 's'} saved on this device. '
                'They will sync when you reconnect.',
        action: conn.forcedOffline ? 'Go Online' : null,
        onAction: conn.forcedOffline ? () => conn.setForcedOffline(false) : null,
      );
    }
    if (sync.phase == SyncPhase.error) {
      return card(
        CupertinoColors.systemRed,
        CupertinoIcons.exclamationmark_circle,
        'Sync Problem',
        pending == 0
            ? 'Could not reach the server. Retrying automatically.'
            : 'Could not upload $pending change${pending == 1 ? '' : 's'} yet. '
                'They are safe on this device and will retry automatically.',
        action: 'Retry',
        onAction: () => sync.syncNow(force: true),
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
