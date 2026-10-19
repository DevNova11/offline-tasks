import 'package:flutter/cupertino.dart';

import '../models/task.dart';

/// iOS look: Cupertino system colours, grouped backgrounds, SF-style type.
/// Brightness follows the device setting (light / dark).
class AppTheme {
  static const cupertino = CupertinoThemeData(
    primaryColor: CupertinoColors.systemBlue,
    scaffoldBackgroundColor: CupertinoColors.systemGroupedBackground,
  );
}

/// Resolves a dynamic system colour for the current brightness.
Color resolve(BuildContext context, Color c) =>
    CupertinoDynamicColor.resolve(c, context);

Color priorityColor(Priority p) => switch (p) {
      Priority.high => CupertinoColors.systemRed,
      Priority.medium => CupertinoColors.systemOrange,
      Priority.low => CupertinoColors.systemGreen,
    };

String priorityLabel(Priority p) => switch (p) {
      Priority.high => 'High',
      Priority.medium => 'Medium',
      Priority.low => 'Low',
    };

/// Reminders-style "!!!" marks.
String priorityMarks(Priority p) => switch (p) {
      Priority.high => '!!!',
      Priority.medium => '!!',
      Priority.low => '!',
    };

String recurrenceLabel(Recurrence r) => switch (r) {
      Recurrence.none => 'Never',
      Recurrence.daily => 'Daily',
      Recurrence.weekly => 'Weekly',
      Recurrence.monthly => 'Monthly',
    };

class AppText {
  static TextStyle body(BuildContext c) =>
      CupertinoTheme.of(c).textTheme.textStyle;

  static TextStyle secondary(BuildContext c, {double size = 13}) => TextStyle(
        fontSize: size,
        color: resolve(c, CupertinoColors.secondaryLabel),
        letterSpacing: -0.08,
      );

  static TextStyle sectionHeader(BuildContext c) => TextStyle(
        fontSize: 13,
        color: resolve(c, CupertinoColors.secondaryLabel),
        letterSpacing: -0.08,
      );
}
