import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/task_repository.dart';
import '../models/task.dart';
import 'theme.dart';
import 'widgets/task_tile.dart';

class TaskEditorScreen extends StatefulWidget {
  const TaskEditorScreen({super.key, this.task});

  /// Null to create a new task.
  final Task? task;

  @override
  State<TaskEditorScreen> createState() => _TaskEditorScreenState();
}

class _TaskEditorScreenState extends State<TaskEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.task?.title);
  late final _description = TextEditingController(text: widget.task?.description);
  late final _category = TextEditingController(text: widget.task?.category);
  final _tagInput = TextEditingController();

  late Priority _priority = widget.task?.priority ?? Priority.medium;
  late DateTime? _dueAt = widget.task?.dueAt;
  late List<String> _tags = [...?widget.task?.tags];
  late Recurrence _recurrence = widget.task?.recurrence ?? Recurrence.none;
  bool _saving = false;

  bool get _isNew => widget.task == null;

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
        (_category.text.trim().isEmpty ? null : _category.text.trim()) != o.category ||
        _tags.join(',') != o.tags.join(',') ||
        _recurrence != o.recurrence;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = context.read<TaskRepository>();
    final category = _category.text.trim().isEmpty ? null : _category.text.trim();

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

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final initial = _dueAt ?? DateTime(now.year, now.month, now.day, now.hour + 1);
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted) return;
    final t = time ?? const TimeOfDay(hour: 9, minute: 0);
    setState(() => _dueAt = DateTime(date.year, date.month, date.day, t.hour, t.minute));
  }

  void _addTag(String raw) {
    final tag = raw.trim().replaceAll('#', '').replaceAll(' ', '-').toLowerCase();
    if (tag.isEmpty || _tags.contains(tag)) {
      _tagInput.clear();
      return;
    }
    setState(() {
      _tags = [..._tags, tag];
      _tagInput.clear();
    });
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Discard changes?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep editing')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Discard')),
        ],
      ),
    );
    return r ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<TaskRepository>();
    final latest = _isNew ? null : repo.recordOf(widget.task!.id)?.task;
    final changedElsewhere = latest != null &&
        !latest.sameContentAs(widget.task!) &&
        latest.lastModifiedBy != repo.deviceId;
    final categories = repo.allCategories.toList()..sort();
    final suggestedTags = repo.allTags.where((t) => !_tags.contains(t)).toList()..sort();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmDiscard()) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? 'New task' : 'Edit task'),
          actions: [
            if (!_isNew)
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  Navigator.of(context).pop();
                  deleteWithUndo(context, widget.task!);
                },
              ),
            TextButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save'),
            ),
          ],
        ),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (changedElsewhere)
                Card(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: const ListTile(
                    leading: Icon(Icons.sync),
                    title: Text('Updated from another device'),
                    subtitle: Text('Only the fields you change here will be saved; '
                        'the other updates are kept.'),
                  ),
                ),
              TextFormField(
                controller: _title,
                autofocus: _isNew,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Give the task a title' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
              ),
              const SizedBox(height: 20),
              Text('Priority', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<Priority>(
                segments: [
                  for (final p in Priority.values)
                    ButtonSegment(
                      value: p,
                      label: Text(priorityLabel(p)),
                      icon: Icon(Icons.flag,
                          color: priorityColor(p, Theme.of(context).colorScheme)),
                    ),
                ],
                selected: {_priority},
                onSelectionChanged: (s) => setState(() => _priority = s.first),
              ),
              const SizedBox(height: 20),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.event),
                      title: Text(_dueAt == null
                          ? 'No deadline'
                          : DateFormat.yMMMEd().add_jm().format(_dueAt!)),
                      subtitle: _dueAt == null
                          ? null
                          : const Text('Reminders 30 min before and when due'),
                      trailing: _dueAt == null
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(() => _dueAt = null),
                            ),
                      onTap: _pickDue,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.repeat),
                      title: DropdownButtonHideUnderline(
                        child: DropdownButton<Recurrence>(
                          value: _recurrence,
                          isExpanded: true,
                          items: [
                            for (final r in Recurrence.values)
                              DropdownMenuItem(value: r, child: Text(recurrenceLabel(r))),
                          ],
                          onChanged: (r) => setState(() => _recurrence = r!),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Autocomplete<String>(
                initialValue: TextEditingValue(text: _category.text),
                optionsBuilder: (v) => categories.where(
                    (c) => c.toLowerCase().contains(v.text.toLowerCase())),
                onSelected: (c) => _category.text = c,
                fieldViewBuilder: (context, controller, focus, onSubmit) {
                  return TextField(
                    controller: controller,
                    focusNode: focus,
                    onChanged: (v) => _category.text = v,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Category (optional)',
                      prefixIcon: Icon(Icons.folder_outlined),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _tagInput,
                decoration: InputDecoration(
                  labelText: 'Add tag',
                  prefixIcon: const Icon(Icons.sell_outlined),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => _addTag(_tagInput.text),
                  ),
                ),
                onSubmitted: _addTag,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in _tags)
                    InputChip(
                      label: Text('#$t'),
                      onDeleted: () => setState(() => _tags = [..._tags]..remove(t)),
                    ),
                  for (final t in suggestedTags.take(8))
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 14),
                      label: Text('#$t'),
                      onPressed: () => _addTag(t),
                    ),
                ],
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.check),
                label: Text(_isNew ? 'Create task' : 'Save changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
