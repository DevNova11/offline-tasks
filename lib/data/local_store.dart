import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import '../models/local_record.dart';
import '../models/sync_log_entry.dart';

/// Persistent on-device storage (Hive). The single source of truth for the UI.
///
/// Every record is stored as one JSON string under the task id, so a task,
/// its last-synced base and its pending sync op are always written together.
class LocalStore {
  LocalStore._(this._records, this._meta, this._log);

  static const _maxLogEntries = 300;

  final Box<String> _records;
  final Box<String> _meta;
  final Box<String> _log;

  /// Opens the boxes. [prefix] lets tests use isolated boxes.
  static Future<LocalStore> open({String prefix = ''}) async {
    final records = await Hive.openBox<String>('${prefix}records');
    final meta = await Hive.openBox<String>('${prefix}meta');
    final log = await Hive.openBox<String>('${prefix}sync_log');
    return LocalStore._(records, meta, log);
  }

  // ---- records ----

  List<LocalRecord> allRecords() => _records.values
      .map((s) => LocalRecord.fromJson(jsonDecode(s) as Map<String, dynamic>))
      .toList();

  LocalRecord? record(String id) {
    final s = _records.get(id);
    return s == null
        ? null
        : LocalRecord.fromJson(jsonDecode(s) as Map<String, dynamic>);
  }

  Future<void> putRecord(LocalRecord r) async {
    await _records.put(r.task.id, jsonEncode(r.toJson()));
    await _records.flush();
  }

  Future<void> putRecords(Iterable<LocalRecord> rs) async {
    await _records.putAll({for (final r in rs) r.task.id: jsonEncode(r.toJson())});
    await _records.flush();
  }

  Future<void> deleteRecord(String id) => _records.delete(id);

  // ---- metadata ----

  String get deviceId {
    var id = _meta.get('deviceId');
    if (id == null) {
      id = const Uuid().v4().substring(0, 8);
      _meta.put('deviceId', id);
    }
    return id;
  }

  /// Server timestamp (ms) of the newest change already pulled.
  int get pullCursor => int.tryParse(_meta.get('pullCursor') ?? '') ?? 0;
  Future<void> setPullCursor(int v) => _meta.put('pullCursor', '$v');

  /// The account the local data was last synced with.
  String? get syncedUid => _meta.get('syncedUid');
  Future<void> setSyncedUid(String? v) =>
      v == null ? _meta.delete('syncedUid') : _meta.put('syncedUid', v);

  DateTime? get lastSyncAt {
    final v = int.tryParse(_meta.get('lastSyncAt') ?? '');
    return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
  }

  Future<void> setLastSyncAt(DateTime v) =>
      _meta.put('lastSyncAt', '${v.millisecondsSinceEpoch}');

  bool get forcedOffline => _meta.get('forcedOffline') == 'true';
  Future<void> setForcedOffline(bool v) => _meta.put('forcedOffline', '$v');

  String? getPref(String key) => _meta.get('pref.$key');
  Future<void> setPref(String key, String value) => _meta.put('pref.$key', value);

  // ---- sync log ----

  List<SyncLogEntry> logEntries() => _log.values
      .map((s) => SyncLogEntry.fromJson(jsonDecode(s) as Map<String, dynamic>))
      .toList()
      .reversed
      .toList();

  Future<void> addLog(SyncLogEntry e) async {
    await _log.add(jsonEncode(e.toJson()));
    if (_log.length > _maxLogEntries) {
      await _log.deleteAll(_log.keys.take(_log.length - _maxLogEntries).toList());
    }
  }

  Future<void> clearLog() => _log.clear();
}
