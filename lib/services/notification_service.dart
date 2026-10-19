import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/task.dart' show Task;

/// Local deadline reminders: one 30 minutes before the deadline and one at
/// the deadline. Works offline; schedules follow every local or synced change.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'deadlines',
      'Task deadlines',
      channelDescription: 'Reminders before and when a task is due',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  int _id(String taskId, int slot) =>
      (taskId.hashCode & 0x3fffffff) * 2 + slot;

  Future<void> sync(Task t) async {
    if (!_ready) return;
    await _plugin.cancel(id: _id(t.id, 0));
    await _plugin.cancel(id: _id(t.id, 1));
    final due = t.dueAt;
    if (t.deleted || t.completed || due == null) return;

    final reminders = {
      0: (due.subtract(const Duration(minutes: 30)), 'Due in 30 minutes'),
      1: (due, 'Due now'),
    };
    for (final MapEntry(key: slot, value: (at, label)) in reminders.entries) {
      if (!at.isAfter(DateTime.now())) continue;
      await _plugin.zonedSchedule(
        id: _id(t.id, slot),
        title: t.title,
        body: label,
        scheduledDate: tz.TZDateTime.from(at, tz.local),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  Future<void> syncAll(Iterable<Task> tasks) async {
    for (final t in tasks) {
      await sync(t);
    }
  }
}
