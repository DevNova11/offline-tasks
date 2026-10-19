import 'package:flutter/material.dart';

import '../models/task.dart';

class AppTheme {
  static const _seed = Color(0xFF3D5AFE);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: b);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }
}

Color priorityColor(Priority p, ColorScheme s) => switch (p) {
      Priority.high => const Color(0xFFE53935),
      Priority.medium => const Color(0xFFFB8C00),
      Priority.low => const Color(0xFF43A047),
    };

String priorityLabel(Priority p) => switch (p) {
      Priority.high => 'High',
      Priority.medium => 'Medium',
      Priority.low => 'Low',
    };

String recurrenceLabel(Recurrence r) => switch (r) {
      Recurrence.none => 'Does not repeat',
      Recurrence.daily => 'Every day',
      Recurrence.weekly => 'Every week',
      Recurrence.monthly => 'Every month',
    };
