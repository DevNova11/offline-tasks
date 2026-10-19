import 'package:flutter_test/flutter_test.dart';
import 'package:offline_tasks/models/task.dart';
import 'package:offline_tasks/sync/merge.dart';

void main() {
  final t0 = DateTime(2026, 10, 1, 9);
  final base = Task(
    id: 'a',
    title: 'Buy milk',
    tags: const ['home', 'errand'],
    sortOrder: 0,
    createdAt: t0,
    updatedAt: t0,
    lastModifiedBy: 'dev1',
  );
  DateTime at(int min) => t0.add(Duration(minutes: min));

  test('edits to different fields are both kept', () {
    final local = base.copyWith(title: 'Buy oat milk', updatedAt: at(1));
    final remote = base.copyWith(priority: Priority.high, updatedAt: at(2));
    final r = mergeTasks(base: base, local: local, remote: remote);
    expect(r.task.title, 'Buy oat milk');
    expect(r.task.priority, Priority.high);
    expect(r.hadTrueConflict, isFalse);
  });

  test('same field changed on both sides: newest edit wins', () {
    final local = base.copyWith(title: 'Local title', updatedAt: at(5));
    final remote = base.copyWith(title: 'Remote title', updatedAt: at(3));
    final r = mergeTasks(base: base, local: local, remote: remote);
    expect(r.task.title, 'Local title');
    expect(r.conflictingFields, ['title']);

    final r2 = mergeTasks(
        base: base, local: local.copyWith(updatedAt: at(1)), remote: remote);
    expect(r2.task.title, 'Remote title');
  });

  test('both devices resolve a conflict identically', () {
    final a = base.copyWith(title: 'A', updatedAt: at(1), lastModifiedBy: 'dev1');
    final b = base.copyWith(title: 'B', updatedAt: at(1), lastModifiedBy: 'dev2');
    final onA = mergeTasks(base: base, local: a, remote: b).task;
    final onB = mergeTasks(base: base, local: b, remote: a).task;
    expect(onA.title, onB.title);
  });

  test('tags are set-merged: additions and removals from both sides', () {
    final local = base.copyWith(tags: ['home', 'errand', 'urgent'], updatedAt: at(1));
    final remote = base.copyWith(tags: ['home', 'weekend'], updatedAt: at(2));
    final r = mergeTasks(base: base, local: local, remote: remote);
    expect(r.task.tags.toSet(), {'home', 'urgent', 'weekend'});
  });

  test('delete wins over an older edit', () {
    final local = base.copyWith(deleted: true, updatedAt: at(5));
    final remote = base.copyWith(title: 'edited', updatedAt: at(2));
    expect(mergeTasks(base: base, local: local, remote: remote).task.deleted, isTrue);
  });

  test('an edit made after a delete restores the task', () {
    final local = base.copyWith(deleted: true, updatedAt: at(1));
    final remote = base.copyWith(title: 'edited later', updatedAt: at(5));
    final r = mergeTasks(base: base, local: local, remote: remote);
    expect(r.task.deleted, isFalse);
    expect(r.task.title, 'edited later');
  });

  test('completion keeps its timestamp from the side that completed', () {
    final local = base.copyWith(completed: true, completedAt: at(4), updatedAt: at(4));
    final remote = base.copyWith(description: 'notes', updatedAt: at(2));
    final r = mergeTasks(base: base, local: local, remote: remote);
    expect(r.task.completed, isTrue);
    expect(r.task.completedAt, at(4));
    expect(r.task.description, 'notes');
  });
}
