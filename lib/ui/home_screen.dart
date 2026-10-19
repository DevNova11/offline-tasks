import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/remote_store.dart';
import '../data/task_repository.dart';
import '../models/local_record.dart';
import '../models/task.dart';
import '../sync/sync_engine.dart';
import 'settings_screen.dart';
import 'sync_activity_screen.dart';
import 'task_editor_screen.dart';
import 'task_filter.dart';
import 'theme.dart';
import 'widgets/sync_status.dart';
import 'widgets/task_tile.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final _search =
      TextEditingController(text: context.read<TaskFilter>().query);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openEditor([Task? task]) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TaskEditorScreen(task: task)),
      );

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<TaskRepository>();
    final filter = context.watch<TaskFilter>();
    final all = repo.tasks;
    final visible = filter.apply(all);
    final records = [for (final t in visible) repo.recordOf(t.id)!];
    final pendingCount = all.where((t) => !t.completed).length;
    final doneCount = all.length - pendingCount;
    final canReorder = filter.sort == SortMode.manual && !filter.isFiltering;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        actions: [
          const SyncStatusButton(),
          PopupMenuButton<String>(
            onSelected: (v) => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => v == 'log'
                  ? const SyncActivityScreen()
                  : const SettingsScreen(),
            )),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'log', child: Text('Sync activity')),
              PopupMenuItem(value: 'settings', child: Text('Settings & account')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          const ConnectivityBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SearchBar(
              controller: _search,
              hintText: 'Search tasks, tags, categories',
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              trailing: [
                if (filter.query.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _search.clear();
                      filter.query = '';
                    },
                  ),
              ],
              onChanged: (v) => filter.query = v,
            ),
          ),
          _FilterBar(repo: repo, filter: filter),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
            child: Row(
              children: [
                Text('$pendingCount pending · $doneCount done',
                    style: Theme.of(context).textTheme.labelMedium),
                const Spacer(),
                if (canReorder && visible.length > 1)
                  Text('Drag ≡ to reorder',
                      style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? _EmptyState(
                    filtered: all.isNotEmpty,
                    onCreate: () => _openEditor(),
                    onClear: () {
                      _search.clear();
                      filter.clear();
                    },
                  )
                : RefreshIndicator(
                    onRefresh: () =>
                        context.read<SyncEngine>().syncNow(force: true),
                    child: canReorder
                        ? _reorderableList(records)
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(bottom: 88),
                            itemCount: records.length,
                            itemBuilder: (_, i) => _tile(records[i]),
                          ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('New task'),
      ),
    );
  }

  Widget _tile(LocalRecord r, {Widget? handle}) => TaskTile(
        key: ValueKey(r.task.id),
        record: r,
        onTap: () => _openEditor(r.task),
        onLongPress: () => _showActions(r.task),
        dragHandle: handle,
      );

  Widget _reorderableList(List<LocalRecord> records) {
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: records.length,
      itemBuilder: (_, i) => _tile(
        records[i],
        handle: ReorderableDragStartListener(
          index: i,
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.drag_handle),
          ),
        ),
      ),
      onReorderItem: (oldIndex, newIndex) {
        final tasks = [for (final r in records) r.task];
        final moved = tasks.removeAt(oldIndex);
        tasks.insert(newIndex, moved);
        context.read<TaskRepository>().moveBetween(
              moved,
              newIndex > 0 ? tasks[newIndex - 1] : null,
              newIndex < tasks.length - 1 ? tasks[newIndex + 1] : null,
            );
      },
    );
  }

  void _showActions(Task t) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('Priority ${priorityLabel(t.priority)}'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(sheet);
                _openEditor(t);
              },
            ),
            ListTile(
              leading: Icon(t.completed ? Icons.undo : Icons.check),
              title: Text(t.completed ? 'Mark as pending' : 'Mark as complete'),
              onTap: () {
                Navigator.pop(sheet);
                context.read<TaskRepository>().setCompleted(t, !t.completed);
              },
            ),
            ListTile(
              leading: const Icon(Icons.devices_other),
              title: const Text('Simulate edit from another device'),
              subtitle: const Text('Changes the server copy, for testing conflicts'),
              onTap: () async {
                Navigator.pop(sheet);
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await context.read<SyncEngine>().simulateRemoteEdit(t);
                  messenger.showSnackBar(const SnackBar(
                      content: Text('Server copy changed. It will arrive as a remote update.')));
                } on RemoteUnavailable catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text(e.message)));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(sheet);
                deleteWithUndo(context, t);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.repo, required this.filter});
  final TaskRepository repo;
  final TaskFilter filter;

  @override
  Widget build(BuildContext context) {
    final tags = repo.allTags.toList()..sort();
    final categories = repo.allCategories.toList()..sort();

    Widget menuChip<T>({
      required String label,
      required IconData icon,
      required T? value,
      required List<T> options,
      required String Function(T) name,
      required void Function(T?) onSelect,
    }) {
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: PopupMenuButton<Object>(
          onSelected: (v) => onSelect(v is T ? v as T : null),
          itemBuilder: (_) => [
            PopupMenuItem(value: '_any', child: Text('Any $label'.toLowerCase())),
            for (final o in options)
              CheckedPopupMenuItem(value: o, checked: o == value, child: Text(name(o))),
          ],
          child: Chip(
            avatar: Icon(icon, size: 16),
            label: Text(value == null ? label : name(value)),
            backgroundColor: value == null
                ? null
                : Theme.of(context).colorScheme.secondaryContainer,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (final s in StatusFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(switch (s) {
                  StatusFilter.all => 'All',
                  StatusFilter.pending => 'Pending',
                  StatusFilter.completed => 'Done',
                }),
                selected: filter.status == s,
                onSelected: (_) => filter.status = s,
              ),
            ),
          menuChip<Priority>(
            label: 'Priority',
            icon: Icons.flag_outlined,
            value: filter.priority,
            options: Priority.values.reversed.toList(),
            name: priorityLabel,
            onSelect: (v) => filter.priority = v,
          ),
          if (categories.isNotEmpty || filter.category != null)
            menuChip<String>(
              label: 'Category',
              icon: Icons.folder_outlined,
              value: filter.category,
              options: categories,
              name: (c) => c,
              onSelect: (v) => filter.category = v,
            ),
          if (tags.isNotEmpty || filter.tag != null)
            menuChip<String>(
              label: 'Tag',
              icon: Icons.sell_outlined,
              value: filter.tag,
              options: tags,
              name: (t) => '#$t',
              onSelect: (v) => filter.tag = v,
            ),
          menuChip<SortMode>(
            label: 'Sort',
            icon: Icons.sort,
            value: filter.sort,
            options: SortMode.values,
            name: (s) => switch (s) {
              SortMode.manual => 'My order',
              SortMode.dueDate => 'Due date',
              SortMode.priority => 'Priority',
              SortMode.created => 'Newest',
            },
            onSelect: (v) => filter.sort = v ?? SortMode.manual,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.filtered,
    required this.onCreate,
    required this.onClear,
  });

  final bool filtered;
  final VoidCallback onCreate;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(filtered ? Icons.filter_alt_off_outlined : Icons.task_alt,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(filtered ? 'No tasks match' : 'No tasks yet',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              filtered
                  ? 'Try a different search or clear the filters.'
                  : 'Add your first task. It works offline too: '
                      'everything is saved on this device and synced when you are online.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            filtered
                ? OutlinedButton(onPressed: onClear, child: const Text('Clear filters'))
                : FilledButton.icon(
                    onPressed: onCreate,
                    icon: const Icon(Icons.add),
                    label: const Text('Add a task'),
                  ),
          ],
        ),
      ),
    );
  }
}
