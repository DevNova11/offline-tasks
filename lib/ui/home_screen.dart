import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
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
import 'widgets/ios.dart';
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
        CupertinoPageRoute(
          fullscreenDialog: task == null,
          builder: (_) => TaskEditorScreen(task: task),
        ),
      );

  void _open(Widget screen) =>
      Navigator.of(context).push(CupertinoPageRoute(builder: (_) => screen));

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
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return CupertinoPageScaffold(
      child: Stack(
        children: [
          CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            slivers: [
              CupertinoSliverNavigationBar(
                largeTitle: const Text('Tasks'),
                border: null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SyncStatusPill(),
                    CupertinoButton(
                      padding: const EdgeInsets.only(left: 8),
                      minimumSize: const Size(0, 0),
                      onPressed: _showMenu,
                      child: const Icon(CupertinoIcons.ellipsis_circle, size: 25),
                    ),
                  ],
                ),
              ),
              CupertinoSliverRefreshControl(
                onRefresh: () => context.read<SyncEngine>().syncNow(force: true),
              ),
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ConnectivityBanner(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: CupertinoSearchTextField(
                        controller: _search,
                        placeholder: 'Search',
                        onChanged: (v) => filter.query = v,
                        onSuffixTap: () {
                          _search.clear();
                          filter.query = '';
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: CupertinoSlidingSegmentedControl<StatusFilter>(
                        groupValue: filter.status,
                        onValueChanged: (v) => filter.status = v ?? StatusFilter.all,
                        children: const {
                          StatusFilter.all: Text('All'),
                          StatusFilter.pending: Text('Pending'),
                          StatusFilter.completed: Text('Completed'),
                        },
                      ),
                    ),
                    _FilterPills(repo: repo, filter: filter),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 6, 32, 6),
                      child: Row(
                        children: [
                          SectionHeader('$pendingCount pending · $doneCount completed'),
                          const Spacer(),
                          if (canReorder && visible.length > 1)
                            Text('Hold ≡ to reorder',
                                style: AppText.secondary(context, size: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (visible.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(
                    filtered: all.isNotEmpty,
                    onCreate: () => _openEditor(),
                    onClear: () {
                      _search.clear();
                      filter.clear();
                    },
                  ),
                )
              else if (canReorder)
                _reorderableList(records)
              else
                SliverList.builder(
                  itemCount: records.length,
                  itemBuilder: (_, i) => _tile(records, i),
                ),
              SliverToBoxAdapter(child: SizedBox(height: 90 + bottomInset)),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomBar(onNew: () => _openEditor()),
          ),
        ],
      ),
    );
  }

  Widget _tile(List<LocalRecord> records, int i, {Widget? handle}) {
    final r = records[i];
    return TaskTile(
      key: ValueKey(r.task.id),
      record: r,
      isFirst: i == 0,
      isLast: i == records.length - 1,
      onTap: () => _openEditor(r.task),
      onLongPress: () => _showActions(r.task),
      dragHandle: handle,
    );
  }

  Widget _reorderableList(List<LocalRecord> records) {
    return SliverReorderableList(
      itemCount: records.length,
      proxyDecorator: (child, _, anim) => AnimatedBuilder(
        animation: anim,
        builder: (_, c) => DecoratedBox(
          decoration: BoxDecoration(boxShadow: [
            BoxShadow(
              color: const Color(0x33000000),
              blurRadius: 18 * anim.value,
              offset: const Offset(0, 6),
            ),
          ]),
          child: c,
        ),
        child: child,
      ),
      itemBuilder: (context, i) => _tile(
        records,
        i,
        handle: ReorderableDragStartListener(
          index: i,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
            child: Icon(CupertinoIcons.line_horizontal_3,
                size: 20, color: resolve(context, CupertinoColors.systemGrey2)),
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

  void _showMenu() {
    final sync = context.read<SyncEngine>();
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              sync.syncNow(force: true);
            },
            child: const Text('Sync Now'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _open(const SyncActivityScreen());
            },
            child: const Text('Sync Activity'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _open(const SettingsScreen());
            },
            child: const Text('Settings & Account'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _showActions(Task t) {
    final repo = context.read<TaskRepository>();
    final sync = context.read<SyncEngine>();
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        message: Text('${priorityLabel(t.priority)} priority'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _openEditor(t);
            },
            child: const Text('Edit'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              repo.setCompleted(t, !t.completed);
            },
            child: Text(t.completed ? 'Mark as Pending' : 'Mark as Completed'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await sync.simulateRemoteEdit(t);
                if (mounted) {
                  showToast(context,
                      'Server copy changed. It will arrive as a remote update.');
                }
              } on RemoteUnavailable catch (e) {
                if (mounted) showToast(context, e.message);
              }
            },
            child: const Text('Simulate Edit from Another Device'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              deleteWithUndo(context, t);
            },
            child: const Text('Delete'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
}

class _FilterPills extends StatelessWidget {
  const _FilterPills({required this.repo, required this.filter});
  final TaskRepository repo;
  final TaskFilter filter;

  static String sortLabel(SortMode s) => switch (s) {
        SortMode.manual => 'Manual',
        SortMode.dueDate => 'Due Date',
        SortMode.priority => 'Priority',
        SortMode.created => 'Newest',
      };

  @override
  Widget build(BuildContext context) {
    final tags = repo.allTags.toList()..sort();
    final categories = repo.allCategories.toList()..sort();

    Future<void> pick<T>(String title, List<T> options, T? current,
        String Function(T) label, void Function(T?) set) async {
      final r = await pickFromSheetWithClear<T>(
        context,
        title: title,
        options: options,
        label: label,
        selected: current,
        clearLabel: 'Any',
      );
      if (r != null) set(r.value);
    }

    final pills = <Widget>[
      Pill(
        icon: CupertinoIcons.arrow_up_arrow_down,
        label: sortLabel(filter.sort),
        onTap: () async {
          final s = await pickFromSheet<SortMode>(
            context,
            title: 'Sort By',
            options: SortMode.values,
            label: sortLabel,
            selected: filter.sort,
          );
          if (s != null) filter.sort = s;
        },
      ),
      Pill(
        icon: CupertinoIcons.flag,
        label: filter.priority == null ? 'Priority' : priorityLabel(filter.priority!),
        selected: filter.priority != null,
        color: filter.priority == null ? null : priorityColor(filter.priority!),
        onTap: () => pick<Priority>('Priority', Priority.values.reversed.toList(),
            filter.priority, priorityLabel, (v) => filter.priority = v),
      ),
      if (categories.isNotEmpty || filter.category != null)
        Pill(
          icon: CupertinoIcons.folder,
          label: filter.category ?? 'Category',
          selected: filter.category != null,
          onTap: () => pick<String>('Category', categories, filter.category,
              (c) => c, (v) => filter.category = v),
        ),
      if (tags.isNotEmpty || filter.tag != null)
        Pill(
          icon: CupertinoIcons.tag,
          label: filter.tag == null ? 'Tag' : '#${filter.tag}',
          selected: filter.tag != null,
          onTap: () => pick<String>(
              'Tag', tags, filter.tag, (t) => '#$t', (v) => filter.tag = v),
        ),
    ];

    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        itemCount: pills.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => pills[i],
      ),
    );
  }
}

/// Translucent bottom toolbar with the Reminders-style "New Task" button.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.onNew});
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.fromLTRB(8, 4, 8, bottom + 4),
          decoration: BoxDecoration(
            color: resolve(context, CupertinoColors.systemGroupedBackground)
                .withValues(alpha: 0.85),
            border: Border(
              top: BorderSide(
                  color: resolve(context, CupertinoColors.separator), width: 0.5),
            ),
          ),
          child: Row(
            children: [
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: onNew,
                child: const Row(
                  children: [
                    Icon(CupertinoIcons.add_circled_solid, size: 26),
                    SizedBox(width: 8),
                    Text('New Task',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 40, 40, 120),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            filtered ? CupertinoIcons.search : CupertinoIcons.checkmark_circle,
            size: 56,
            color: resolve(context, CupertinoColors.systemGrey3),
          ),
          const SizedBox(height: 14),
          Text(
            filtered ? 'No Results' : 'No Tasks',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            filtered
                ? 'Try a different search or clear the filters.'
                : 'Tasks you add appear here. Everything works offline and syncs '
                    'when you are online.',
            textAlign: TextAlign.center,
            style: AppText.secondary(context, size: 15),
          ),
          const SizedBox(height: 18),
          filtered
              ? CupertinoButton(onPressed: onClear, child: const Text('Clear Filters'))
              : CupertinoButton.filled(
                  onPressed: onCreate,
                  child: const Text('Add a Task'),
                ),
        ],
      ),
    );
  }
}
