enum SyncLogKind { push, pull, conflict, retry, error, recovery, info }

class SyncLogEntry {
  SyncLogEntry({
    required this.at,
    required this.kind,
    required this.message,
    this.taskId,
  });

  final DateTime at;
  final SyncLogKind kind;
  final String message;
  final String? taskId;

  Map<String, dynamic> toJson() => {
        'at': at.millisecondsSinceEpoch,
        'kind': kind.name,
        'message': message,
        'taskId': taskId,
      };

  factory SyncLogEntry.fromJson(Map<String, dynamic> j) => SyncLogEntry(
        at: DateTime.fromMillisecondsSinceEpoch(j['at'] as int),
        kind: SyncLogKind.values.asNameMap()[j['kind']] ?? SyncLogKind.info,
        message: j['message'] as String,
        taskId: j['taskId'] as String?,
      );
}
