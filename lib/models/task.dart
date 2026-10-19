import 'package:flutter/foundation.dart';

enum Priority { low, medium, high }

enum Recurrence { none, daily, weekly, monthly }

/// A task as the user sees it. Immutable; every edit produces a new copy.
///
/// The [id] is a client-generated UUID, so a task has the same identity on
/// every device and on the server from the moment it is created. That is what
/// makes retried uploads idempotent and keeps duplicates out.
@immutable
class Task {
  const Task({
    required this.id,
    required this.title,
    this.description = '',
    this.priority = Priority.medium,
    this.dueAt,
    this.category,
    this.tags = const [],
    this.completed = false,
    this.completedAt,
    this.recurrence = Recurrence.none,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
    this.lastModifiedBy = '',
  });

  final String id;
  final String title;
  final String description;
  final Priority priority;
  final DateTime? dueAt;
  final String? category;
  final List<String> tags;
  final bool completed;
  final DateTime? completedAt;
  final Recurrence recurrence;

  /// Manual ordering key. Fractional, so moving one task only edits that task.
  final double sortOrder;
  final DateTime createdAt;

  /// Client wall-clock time of the last edit; only used as a tie-breaker when
  /// two devices changed the same field.
  final DateTime updatedAt;

  /// Tombstone. Deleted tasks are kept (hidden) so the deletion can sync.
  final bool deleted;

  /// Device id of the last writer.
  final String lastModifiedBy;

  bool get isOverdue =>
      !completed && dueAt != null && dueAt!.isBefore(DateTime.now());

  static const _unset = Object();

  Task copyWith({
    String? title,
    String? description,
    Priority? priority,
    Object? dueAt = _unset,
    Object? category = _unset,
    List<String>? tags,
    bool? completed,
    Object? completedAt = _unset,
    Recurrence? recurrence,
    double? sortOrder,
    DateTime? updatedAt,
    bool? deleted,
    String? lastModifiedBy,
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      dueAt: identical(dueAt, _unset) ? this.dueAt : dueAt as DateTime?,
      category:
          identical(category, _unset) ? this.category : category as String?,
      tags: tags ?? this.tags,
      completed: completed ?? this.completed,
      completedAt: identical(completedAt, _unset)
          ? this.completedAt
          : completedAt as DateTime?,
      recurrence: recurrence ?? this.recurrence,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
      lastModifiedBy: lastModifiedBy ?? this.lastModifiedBy,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'priority': priority.name,
        'dueAt': dueAt?.millisecondsSinceEpoch,
        'category': category,
        'tags': tags,
        'completed': completed,
        'completedAt': completedAt?.millisecondsSinceEpoch,
        'recurrence': recurrence.name,
        'sortOrder': sortOrder,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'deleted': deleted,
        'lastModifiedBy': lastModifiedBy,
      };

  factory Task.fromJson(Map<String, dynamic> j) {
    DateTime? ms(Object? v) =>
        v == null ? null : DateTime.fromMillisecondsSinceEpoch((v as num).toInt());
    return Task(
      id: j['id'] as String,
      title: (j['title'] as String?) ?? '',
      description: (j['description'] as String?) ?? '',
      priority: Priority.values.asNameMap()[j['priority']] ?? Priority.medium,
      dueAt: ms(j['dueAt']),
      category: j['category'] as String?,
      tags: ((j['tags'] as List?) ?? const []).cast<String>().toList(),
      completed: (j['completed'] as bool?) ?? false,
      completedAt: ms(j['completedAt']),
      recurrence:
          Recurrence.values.asNameMap()[j['recurrence']] ?? Recurrence.none,
      sortOrder: ((j['sortOrder'] as num?) ?? 0).toDouble(),
      createdAt: ms(j['createdAt']) ?? DateTime.now(),
      updatedAt: ms(j['updatedAt']) ?? DateTime.now(),
      deleted: (j['deleted'] as bool?) ?? false,
      lastModifiedBy: (j['lastModifiedBy'] as String?) ?? '',
    );
  }

  /// True when the user-visible content is the same (ignores bookkeeping).
  bool sameContentAs(Task o) =>
      title == o.title &&
      description == o.description &&
      priority == o.priority &&
      dueAt == o.dueAt &&
      category == o.category &&
      listEquals(tags, o.tags) &&
      completed == o.completed &&
      completedAt == o.completedAt &&
      recurrence == o.recurrence &&
      sortOrder == o.sortOrder &&
      deleted == o.deleted;
}
