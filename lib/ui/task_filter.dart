import 'package:flutter/foundation.dart';

import '../data/local_store.dart';
import '../models/task.dart';

enum StatusFilter { all, pending, completed }

enum SortMode { manual, dueDate, priority, created }

/// Search, filter and sort state. Lives above the navigator, so it survives
/// opening and closing other screens; the sort mode is also persisted.
class TaskFilter extends ChangeNotifier {
  TaskFilter(this._store)
      : _sort = SortMode.values.asNameMap()[_store.getPref('sort')] ??
            SortMode.manual;

  final LocalStore _store;

  String _query = '';
  StatusFilter _status = StatusFilter.all;
  Priority? _priority;
  String? _tag;
  String? _category;
  SortMode _sort;

  String get query => _query;
  StatusFilter get status => _status;
  Priority? get priority => _priority;
  String? get tag => _tag;
  String? get category => _category;
  SortMode get sort => _sort;

  bool get isFiltering =>
      _query.isNotEmpty ||
      _status != StatusFilter.all ||
      _priority != null ||
      _tag != null ||
      _category != null;

  set query(String v) => _set(() => _query = v);
  set status(StatusFilter v) => _set(() => _status = v);
  set priority(Priority? v) => _set(() => _priority = v);
  set tag(String? v) => _set(() => _tag = v);
  set category(String? v) => _set(() => _category = v);
  set sort(SortMode v) {
    _store.setPref('sort', v.name);
    _set(() => _sort = v);
  }

  void clear() => _set(() {
        _query = '';
        _status = StatusFilter.all;
        _priority = null;
        _tag = null;
        _category = null;
      });

  void _set(VoidCallback f) {
    f();
    notifyListeners();
  }

  List<Task> apply(List<Task> tasks) {
    final q = _query.trim().toLowerCase();
    final out = tasks.where((t) {
      if (_status == StatusFilter.pending && t.completed) return false;
      if (_status == StatusFilter.completed && !t.completed) return false;
      if (_priority != null && t.priority != _priority) return false;
      if (_tag != null && !t.tags.contains(_tag)) return false;
      if (_category != null && t.category != _category) return false;
      if (q.isNotEmpty &&
          !t.title.toLowerCase().contains(q) &&
          !t.description.toLowerCase().contains(q) &&
          !t.tags.any((g) => g.toLowerCase().contains(q)) &&
          !(t.category?.toLowerCase().contains(q) ?? false)) {
        return false;
      }
      return true;
    }).toList();

    int byOrder(Task a, Task b) => a.sortOrder.compareTo(b.sortOrder);
    switch (_sort) {
      case SortMode.manual:
        out.sort(byOrder);
      case SortMode.dueDate:
        out.sort((a, b) {
          if (a.dueAt == null && b.dueAt == null) return byOrder(a, b);
          if (a.dueAt == null) return 1;
          if (b.dueAt == null) return -1;
          return a.dueAt!.compareTo(b.dueAt!);
        });
      case SortMode.priority:
        out.sort((a, b) {
          final c = b.priority.index.compareTo(a.priority.index);
          return c != 0 ? c : byOrder(a, b);
        });
      case SortMode.created:
        out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    // Completed tasks sink to the bottom, except in manual order.
    if (_sort != SortMode.manual) {
      final done = out.where((t) => t.completed).toList();
      out.removeWhere((t) => t.completed);
      out.addAll(done);
    }
    return out;
  }
}
