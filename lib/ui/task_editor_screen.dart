import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/task_repository.dart';
import '../models/task.dart';
import 'theme.dart';
import 'widgets/ios.dart';
import 'widgets/task_tile.dart';

class TaskEditorScreen extends StatefulWidget {
  const TaskEditorScreen({super.key, this.task});

  /// Null to create a new task.
  final Task? task;

  @override
  State<TaskEditorScreen> createState() => _TaskEditorScreenState();
}

class _TaskEditorScreenState extends State<TaskEditorScreen> {
  late final _title = TextEditingController(text: widget.task?.title)
    ..addListener(_rebuild);
  late final _description = TextEditingController(text: widget.task?.description)
    ..addListener(_rebuild);
  late final _category = TextEditingController(text: widget.task?.category)
    ..addListener(_rebuild);
  final _tagInput = TextEditingController();

  late Priority _priority = widget.task?.priority ?? Priority.medium;
  late DateTime? _dueAt = widget.task?.dueAt;
  late List<String> _tags = [...?widget.task?.tags];
  late Recurrence _recurrence = widget.task?.recurrence ?? Recurrence.none;
  bool _showPicker = false;
  bool _saving = false;

  bool get _isNew => widget.task == null;
  bool get _canSave => _title.text.trim().isNotEmpty && !_saving;
  String? get _categoryValue =>
      _category.text.trim().isEmpty ? null : _category.text.trim();

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _category.dispose();
    _tagInput.dispose();
    super.dispose();
  }

  bool get _dirty {
    final o = widget.task;
    if (o == null) {
      return _title.text.trim().isNotEmpty || _description.text.trim().isNotEmpty;
    }
    return _title.text.trim() != o.title ||
        _description.text.trim() != o.description ||
        _priority != o.priority ||
        _dueAt != o.dueAt ||
        _categoryValue != o.category ||
        _tags.join(',') != o.tags.join(',') ||
        _recurrence != o.recurrence;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final repo = context.read<TaskRepository>();
    final category = _categoryValue;

    if (_isNew) {
      await repo.create(
        title: _title.text,
        description: _description.text,
        priority: _priority,
        dueAt: _dueAt,
        category: category,
        tags: _tags,
        recurrence: _recurrence,
      );
    } else {
      // Apply only the fields the user actually changed, on top of the latest
      // version: a sync that landed while this screen was open is not undone.
      final o = widget.task!;
      final latest = repo.recordOf(o.id)?.task ?? o;
      await repo.update(latest.copyWith(
        title: _title.text.trim() != o.title ? _title.text.trim() : null,
        description: _description.text.trim() != o.description
            ? _description.text.trim()
            : null,
        priority: _priority != o.priority ? _priority : null,
        dueAt: _dueAt != o.dueAt ? _dueAt : latest.dueAt,
        category: category != o.category ? category : latest.category,
        tags: _tags.join(',') != o.tags.join(',') ? _tags : null,
        recurrence: _recurrence != o.recurrence ? _recurrence : null,
      ));
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _close() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final nav = Navigator.of(context);
    final discard = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        message: const Text('Are you sure you want to discard your changes?'),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard Changes'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Keep Editing'),
        ),
      ),
    );
    if (discard == true) nav.pop();
  }

  void _toggleDate(bool on) {
    setState(() {
      if (on) {
        final now = DateTime.now();
        _dueAt ??= DateTime(now.year, now.month, now.day, now.hour + 1);
        _showPicker = true;
      } else {
        _dueAt = null;
        _showPicker = false;
      }
    });
  }

  void _addTag(String raw) {
    final tag = raw.trim().replaceAll('#', '').replaceAll(' ', '-').toLowerCase();
    _tagInput.clear();
    if (tag.isEmpty || _tags.contains(tag)) {
      setState(() {});
      return;
    }
    setState(() => _tags = [..._tags, tag]);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<TaskRepository>();
    final latest = _isNew ? null : repo.recordOf(widget.task!.id)?.task;
    final changedElsewhere = latest != null &&
        !latest.sameContentAs(widget.task!) &&
        latest.lastModifiedBy != repo.deviceId;
    final categories = repo.allCategories
        .where((c) => c != _categoryValue)
        .toList()
      ..sort();
    final suggestedTags = repo.allTags.where((t) => !_tags.contains(t)).toList()..sort();
    final blue = resolve(context, CupertinoColors.systemBlue);

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _close,
            child: const Text('Cancel'),
          ),
          middle: Text(_isNew ? 'New Task' : 'Details'),
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _canSave ? _save : null,
            child: Text(_isNew ? 'Add' : 'Done',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              if (changedElsewhere)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: blue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(CupertinoIcons.arrow_2_circlepath, color: blue, size: 20),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Updated from another device. Only the fields you change '
                            'here will be saved; the other updates are kept.',
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Title + notes
              CupertinoListSection.insetGrouped(
                children: [
                  _field(_title,
                      placeholder: 'Title',
                      autofocus: _isNew,
                      style: const TextStyle(fontSize: 17)),
                  _field(_description,
                      placeholder: 'Notes', minLines: 3, maxLines: 6),
                ],
              ),

              // Date, time and repeat
              CupertinoListSection.insetGrouped(
                footer: _dueAt == null
                    ? null
                    : Text('You will be reminded 30 minutes before and when it is due.',
                        style: AppText.secondary(context)),
                children: [
                  CupertinoListTile(
                    leading: _IconBox(CupertinoIcons.calendar, CupertinoColors.systemRed),
                    title: const Text('Date & Time'),
                    subtitle: _dueAt == null
                        ? null
                        : Text(DateFormat('EEE d MMM yyyy, h:mm a').format(_dueAt!),
                            style: TextStyle(color: blue)),
                    trailing: CupertinoSwitch(
                      value: _dueAt != null,
                      onChanged: _toggleDate,
                    ),
                    onTap: _dueAt == null
                        ? () => _toggleDate(true)
                        : () => setState(() => _showPicker = !_showPicker),
                  ),
                  if (_dueAt != null && _showPicker)
                    SizedBox(
                      height: 200,
                      child: CupertinoDatePicker(
                        initialDateTime: _dueAt,
                        mode: CupertinoDatePickerMode.dateAndTime,
                        minuteInterval: 1,
                        onDateTimeChanged: (d) => setState(() => _dueAt = d),
                      ),
                    ),
                  CupertinoListTile(
                    leading: _IconBox(CupertinoIcons.repeat, CupertinoColors.systemGrey),
                    title: const Text('Repeat'),
                    additionalInfo: Text(recurrenceLabel(_recurrence)),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () async {
                      final r = await pickFromSheet<Recurrence>(
                        context,
                        title: 'Repeat',
                        options: Recurrence.values,
                        label: recurrenceLabel,
                        selected: _recurrence,
                      );
                      if (r != null) setState(() => _recurrence = r);
                    },
                  ),
                ],
              ),

              // Priority + category
              CupertinoListSection.insetGrouped(
                footer: categories.isEmpty
                    ? null
                    : Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final c in categories.take(8))
                            Pill(
                              label: c,
                              icon: CupertinoIcons.folder,
                              onTap: null,
                            ).withTap(() => setState(() => _category.text = c)),
                        ],
                      ),
                children: [
                  CupertinoListTile(
                    leading: _IconBox(CupertinoIcons.exclamationmark,
                        priorityColor(_priority)),
                    title: const Text('Priority'),
                    trailing: SizedBox(
                      width: 190,
                      child: CupertinoSlidingSegmentedControl<Priority>(
                        groupValue: _priority,
                        onValueChanged: (p) => setState(() => _priority = p!),
                        children: {
                          for (final p in Priority.values)
                            p: Text(priorityLabel(p), style: const TextStyle(fontSize: 13)),
                        },
                      ),
                    ),
                  ),
                  CupertinoListTile(
                    leading: _IconBox(CupertinoIcons.folder_fill, CupertinoColors.systemIndigo),
                    title: CupertinoTextField.borderless(
                      controller: _category,
                      placeholder: 'Category',
                      padding: EdgeInsets.zero,
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                ],
              ),

              // Tags
              CupertinoListSection.insetGrouped(
                header: const SectionHeader('Tags'),
                footer: suggestedTags.isEmpty
                    ? null
                    : Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final t in suggestedTags.take(8))
                            Pill(label: '#$t', icon: CupertinoIcons.add)
                                .withTap(() => _addTag(t)),
                        ],
                      ),
                children: [
                  CupertinoListTile(
                    leading: _IconBox(CupertinoIcons.number, CupertinoColors.systemBlue),
                    title: CupertinoTextField.borderless(
                      controller: _tagInput,
                      placeholder: 'Add Tag',
                      padding: EdgeInsets.zero,
                      onSubmitted: _addTag,
                    ),
                    trailing: CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                      onPressed: () => _addTag(_tagInput.text),
                      child: const Icon(CupertinoIcons.add_circled, size: 22),
                    ),
                  ),
                  if (_tags.isNotEmpty)
                    Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final t in _tags)
                            _RemovableTag(
                              label: '#$t',
                              onRemove: () =>
                                  setState(() => _tags = [..._tags]..remove(t)),
                            ),
                        ],
                      ),
                    ),
                ],
              ),

              if (!_isNew)
                CupertinoListSection.insetGrouped(
                  children: [
                    CupertinoListTile(
                      title: Center(
                        child: Text('Delete Task',
                            style: TextStyle(
                                color: resolve(context, CupertinoColors.systemRed))),
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        deleteWithUndo(context, widget.task!);
                      },
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c, {
    required String placeholder,
    bool autofocus = false,
    int minLines = 1,
    int maxLines = 1,
    TextStyle? style,
  }) =>
      CupertinoTextField.borderless(
        controller: c,
        placeholder: placeholder,
        autofocus: autofocus,
        minLines: minLines,
        maxLines: maxLines,
        style: style,
        textCapitalization: TextCapitalization.sentences,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      );
}

/// iOS Settings-style coloured icon square.
class _IconBox extends StatelessWidget {
  const _IconBox(this.icon, this.color);
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: resolve(context, color),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Icon(icon, size: 17, color: CupertinoColors.white),
      );
}

class _RemovableTag extends StatelessWidget {
  const _RemovableTag({required this.label, required this.onRemove});
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final blue = resolve(context, CupertinoColors.systemBlue);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: blue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: blue, fontSize: 14)),
          GestureDetector(
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(CupertinoIcons.xmark_circle_fill, size: 17, color: blue),
            ),
          ),
        ],
      ),
    );
  }
}

extension on Pill {
  /// A pill that acts as a plain button (no dropdown chevron).
  Widget withTap(VoidCallback onTap) =>
      GestureDetector(onTap: onTap, child: this);
}
