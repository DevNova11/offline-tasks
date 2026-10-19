import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../theme.dart';

/// iOS-style toast at the bottom of the screen with an optional action
/// (used for "Deleted · Undo" and short confirmations).
void showToast(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 4),
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  _currentToast?.remove();
  late final OverlayEntry entry;
  var removed = false;
  void remove() {
    if (removed) return;
    removed = true;
    entry.remove();
    if (_currentToast == entry) _currentToast = null;
  }

  entry = OverlayEntry(
    builder: (ctx) => _Toast(
      message: message,
      actionLabel: actionLabel,
      onAction: onAction == null
          ? null
          : () {
              onAction();
              remove();
            },
      duration: duration,
      onDone: remove,
    ),
  );
  _currentToast = entry;
  overlay.insert(entry);
}

OverlayEntry? _currentToast;

class _Toast extends StatefulWidget {
  const _Toast({
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.duration,
    required this.onDone,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;
  final VoidCallback onDone;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, () async {
      if (!mounted) return;
      await _anim.reverse();
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom + 70;
    return Positioned(
      left: 16,
      right: 16,
      bottom: bottom,
      child: FadeTransition(
        opacity: _anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.4), end: Offset.zero)
              .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut)),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
            decoration: BoxDecoration(
              color: const Color(0xEE1C1C1E),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 4)),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color: CupertinoColors.white,
                        fontSize: 15,
                        decoration: TextDecoration.none,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
                if (widget.actionLabel != null)
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    onPressed: widget.onAction,
                    child: Text(
                      widget.actionLabel!,
                      style: const TextStyle(
                        color: CupertinoColors.systemYellow,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Round Reminders-style completion button.
class CompletionCircle extends StatelessWidget {
  const CompletionCircle({
    super.key,
    required this.done,
    required this.color,
    required this.onTap,
  });

  final bool done;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? color : null,
            border: Border.all(
              color: done ? color : resolve(context, CupertinoColors.systemGrey3),
              width: 1.6,
            ),
          ),
          child: done
              ? const Icon(CupertinoIcons.checkmark_alt,
                  size: 16, color: CupertinoColors.white)
              : null,
        ),
      ),
    );
  }
}

/// Rounded capsule used for filters and status.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
    this.color,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? CupertinoTheme.of(context).primaryColor;
    final bg = selected
        ? accent
        : resolve(context, CupertinoColors.tertiarySystemFill);
    final fg = selected ? CupertinoColors.white : resolve(context, CupertinoColors.label);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: TextStyle(fontSize: 14, color: fg, fontWeight: FontWeight.w500)),
            if (onTap != null && !selected) ...[
              const SizedBox(width: 2),
              Icon(CupertinoIcons.chevron_down, size: 11, color: fg),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shows an action sheet of options; resolves to the chosen value, or null.
Future<T?> pickFromSheet<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required String Function(T) label,
  T? selected,
}) {
  return showCupertinoModalPopup<T>(
    context: context,
    builder: (ctx) => CupertinoActionSheet(
      title: Text(title),
      actions: [
        for (final o in options)
          CupertinoActionSheetAction(
            isDefaultAction: o == selected,
            onPressed: () => Navigator.pop(ctx, o),
            child: Text(label(o)),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.pop(ctx),
        child: const Text('Cancel'),
      ),
    ),
  );
}

/// Marks "clear the selection" (as opposed to dismissing the sheet).
class _Cleared<T> {}

/// Like [pickFromSheet] but reports whether the user picked "clear".
Future<({bool cleared, T? value})?> pickFromSheetWithClear<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required String Function(T) label,
  T? selected,
  required String clearLabel,
}) async {
  Object? raw;
  await showCupertinoModalPopup<void>(
    context: context,
    builder: (ctx) => CupertinoActionSheet(
      title: Text(title),
      actions: [
        CupertinoActionSheetAction(
          isDefaultAction: selected == null,
          onPressed: () {
            raw = _Cleared<T>();
            Navigator.pop(ctx);
          },
          child: Text(clearLabel),
        ),
        for (final o in options)
          CupertinoActionSheetAction(
            isDefaultAction: o == selected,
            onPressed: () {
              raw = o;
              Navigator.pop(ctx);
            },
            child: Text(label(o)),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.pop(ctx),
        child: const Text('Cancel'),
      ),
    ),
  );
  if (raw == null) return null;
  if (raw is _Cleared) return (cleared: true, value: null);
  return (cleared: false, value: raw as T);
}

/// Grouped-section header in iOS caps style.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: AppText.sectionHeader(context));
}
