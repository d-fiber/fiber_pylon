// Copyright (C) 2026 Fiber
//
// This Source Code Form is subject to the terms of the Mozilla Public License,
// v. 2.0. If a copy of the MPL was not distributed with this file, You can
// obtain one at https://mozilla.org/MPL/2.0/.
//
// What you may do:
// - Use this software for any purpose, including commercially, and build and
//   sell your own products on top of it.
// - Change it, and create new works based on it.
// - Distribute copies of it, with or without your changes.
// - Combine it with files under any other licence, proprietary ones included,
//   and licence that larger work on your own terms.
//
// What you must do in return:
// - Keep this notice on every file you received it on.
// - Publish, under these same terms, the source of every file covered by them
//   that you distribute, including the ones you changed, so that whoever
//   receives your version can obtain that source.
// - Leave Fiber out of it: the name "Fiber", its branding, its logos and its
//   trademarks may not be used to endorse or promote what you build, and this
//   licence grants no right to them.
//
// Disclaimer:
// AS FAR AS THE LAW ALLOWS, THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY
// OR CONDITION OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
// WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR
// NON-INFRINGEMENT. IN NO EVENT SHALL FIBER BE LIABLE FOR ANY DIRECT, INDIRECT,
// INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING BUT NOT
// LIMITED TO LOSS OF USE, DATA, PROFITS, OR BUSINESS INTERRUPTION) ARISING OUT
// OF OR RELATED TO THESE TERMS OR THE USE OR NATURE OF THE SOFTWARE, UNDER ANY
// KIND OF LEGAL CLAIM.
//
// This header is a summary written for convenience. Where it differs from the
// LICENSE file, the LICENSE file governs.

import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:fiber_pylon/fiber_pylon.dart' hide Database;
import 'package:fiber_pylon/src/sdk/clients/local/database/engine/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';
import 'package:uuid/uuid.dart';

enum Status { open, doing, closed }

final class Priority {
  const Priority({required this.level, required this.label});
  final int level;
  final String label;

  static Priority fromJson(Map<String, dynamic> json) =>
      Priority(level: json['level'] as int, label: json['label'] as String);

  Map<String, dynamic> toJson() => {'level': level, 'label': label};
}

const priorityJson = Json<Priority>(fromJson: Priority.fromJson, toJson: _priorityToJson);
Map<String, dynamic> _priorityToJson(Priority priority) => priority.toJson();

final class Todo extends Equatable {
  const Todo({this.id, required this.title, this.done = false, required this.status, required this.priority, this.due});

  final int? id;
  final String title;
  final bool done;
  final Status status;
  final Priority priority;
  final Date? due;

  @override
  List<Object?> get props => [id, title, done, status, priority.level, priority.label, due];
}

final class Tag extends Equatable {
  const Tag({this.id, required this.name});

  final UuidValue? id;
  final String name;

  @override
  List<Object?> get props => [id, name];
}

final class TodoTag {
  const TodoTag({required this.todoId, required this.tagId});

  final int todoId;
  final UuidValue tagId;
}

final class Note extends Equatable {
  const Note({this.id, required this.todoId, required this.body, required this.writtenOn});

  final int? id;
  final int todoId;
  final String body;
  final Date writtenOn;

  @override
  List<Object?> get props => [id, todoId, body, writtenOn];
}

final class Todos extends KeyedTable<Todo, int> {
  Todos() : super('todos');

  late final id = column.key();
  late final title = column.text('title');
  late final done = column.boolean('done').defaultsTo(false);
  late final status = column.enumeration('status', Status.values);
  late final priority = column.json('priority', priorityJson);
  late final due = column.date('due').nullable();

  @override
  List<Field<Object?>> get columns => [id, title, done, status, priority, due];

  @override
  Todo read(Reader row) => Todo(
    id: row(id),
    title: row(title),
    done: row(done),
    status: row(status),
    priority: row(priority),
    due: row(due),
  );

  @override
  List<Assignment> write(Todo todo) => [
    id.toOrGenerate(todo.id),
    title.to(todo.title),
    done.to(todo.done),
    status.to(todo.status),
    priority.to(todo.priority),
    due.to(todo.due),
  ];
}

final class Tags extends KeyedTable<Tag, UuidValue> {
  Tags() : super('tags');

  late final id = column.uuidKey();
  late final name = column.text('name').unique();

  @override
  List<Field<Object?>> get columns => [id, name];

  @override
  Tag read(Reader row) => Tag(id: row(id), name: row(name));

  @override
  List<Assignment> write(Tag tag) => [id.toOrGenerate(tag.id), name.to(tag.name)];
}

final class TodoTags extends TypedTable<TodoTag> {
  TodoTags() : super('todo_tags');

  late final todoId = column.integer('todo_id').references(todos.id, onDelete: ReferentialAction.cascade);
  late final tagId = column.uuid('tag_id').references(tags.id, onDelete: ReferentialAction.cascade);

  @override
  List<Field<Object?>> get columns => [todoId, tagId];

  @override
  List<Field<Object?>> get primaryKey => [todoId, tagId];

  @override
  TodoTag read(Reader row) => TodoTag(todoId: row(todoId), tagId: row(tagId));

  @override
  List<Assignment> write(TodoTag link) => [todoId.to(link.todoId), tagId.to(link.tagId)];
}

final class Notes extends KeyedTable<Note, int> {
  Notes() : super('notes');

  late final id = column.key();
  late final todoId = column.integer('todo_id').references(todos.id, onDelete: ReferentialAction.cascade);
  late final body = column.text('body');
  late final writtenOn = column.date('written_on');

  @override
  List<Field<Object?>> get columns => [id, todoId, body, writtenOn];

  @override
  Note read(Reader row) => Note(id: row(id), todoId: row(todoId), body: row(body), writtenOn: row(writtenOn));

  @override
  List<Assignment> write(Note note) => [
    id.toOrGenerate(note.id),
    todoId.to(note.todoId),
    body.to(note.body),
    writtenOn.to(note.writtenOn),
  ];
}

final todos = Todos();
final tags = Tags();
final todoTags = TodoTags();
final notes = Notes();

final class TodoStore {
  TodoStore() : db = LocalDatabase.declared(name: 'app.db', tables: [todos, tags, todoTags, notes]);

  final LocalDatabase db;

  Future<Todo> add(Todo todo) => todos.on(db).insert(todo);

  Future<Todo?> getById(int id) => todos.on(db).get(id);

  Future<List<Todo>> page({required Status status, required int page, required int size}) => todos
      .on(db)
      .where(todos.status.isEqualTo(status) & todos.done.isEqualTo(false))
      .orderBy([todos.title.asc()])
      .limit(size)
      .offset(page * size)
      .list();

  Future<int> markDone(int id) => todos.on(db).where(todos.id.isEqualTo(id)).update([todos.done.to(true)]);

  Future<Tag> upsertTag(Tag tag) => tags.on(db).upsert(tag);

  Future<bool> delete(int id) => todos.on(db).remove(id);

  Future<int> countOpen() => todos.on(db).where(todos.done.isEqualTo(false)).count();

  Future<bool> exists(int id) => todos.on(db).where(todos.id.isEqualTo(id)).exists();

  Future<Tag> tag(int todoId, String name) => db.transaction((txn) async {
    final tag = await tags.on(txn).insert(Tag(name: name));
    await todoTags.on(txn).insert(TodoTag(todoId: todoId, tagId: tag.id!));
    return tag;
  });

  Future<List<Todo>> withTag(String name) => todos
      .on(db)
      .where(
        todos.id.isInSelect(todoTags.todoId.where(todoTags.tagId.isInSelect(tags.id.where(tags.name.isEqualTo(name))))),
      )
      .list();

  Future<List<Todo>> addAll(List<Todo> list) => todos.on(db).insertAll(list);

  Future<Note> addNote(Note note) => notes.on(db).insert(note);

  Future<List<Note>> notesOf(int todoId) => notes.on(db).where(notes.todoId.isEqualTo(todoId)).list();

  Future<int> tagLinks() => todoTags.on(db).count();
}

void main() {
  late Directory directory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pylon_after_app');
    databaseFactoryFfi.setDatabasesPath(directory.path);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  Todo sample(String title, {Status status = Status.open, Date? due}) => Todo(
    title: title,
    status: status,
    priority: const Priority(level: 2, label: 'normal'),
    due: due,
  );

  test('a fresh store creates its tables', () async {
    final store = TodoStore();
    await store.db.open();
    final saved = await store.add(sample('Ship it'));

    final found = await store.getById(saved.id!);

    expect(found?.title, 'Ship it');
    expect(found?.priority.label, 'normal');
    expect(found?.due, isNull);
    expect(saved.id, isNotNull);
    await store.db.dispose();
  });

  test('a version 1 file gains its due column with no migration code', () async {
    final v1 = LocalDatabase(
      name: 'app.db',
      version: 1,
      onCreate: (db, version) => db.execute(
        'CREATE TABLE todos (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, '
        'done INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL, priority TEXT NOT NULL)',
      ),
    );
    await v1.open();
    await v1.execute('INSERT INTO todos (title, done, status, priority) VALUES (?, ?, ?, ?)', [
      const Value.varchar('Old'),
      Value.boolean(false),
      Value.enum_(Status.open),
      priorityJson.encode(const Priority(level: 1, label: 'low')),
    ]);
    await v1.dispose();

    final v2 = TodoStore();
    await v2.db.open();

    final found = await v2.getById(1);
    expect(found?.title, 'Old');
    expect(found?.due, isNull);
    await v2.db.dispose();
  });

  test('lists a page of open todos, marks one done, counts, checks and deletes', () async {
    final store = TodoStore();
    await store.db.open();
    final saved = await store.addAll([
      sample('C'),
      sample('A', due: const Date(year: 2026, month: 5, day: 4)),
      sample('B'),
      sample('D', status: Status.doing),
    ]);

    final first = await store.page(status: Status.open, page: 0, size: 2);
    expect(first.map((todo) => todo.title), ['A', 'B']);
    expect(first.first.due, const Date(year: 2026, month: 5, day: 4));

    final id = saved[1].id!;
    expect(await store.markDone(id), 1);
    expect(await store.countOpen(), 3);
    expect(await store.exists(id), isTrue);
    expect(await store.delete(id), isTrue);
    expect(await store.exists(id), isFalse);
    await store.db.dispose();
  });

  test('tags a todo in one transaction and lists the todos of a tag', () async {
    final store = TodoStore();
    await store.db.open();
    final saved = await store.add(sample('Ship it'));

    await store.tag(saved.id!, 'work');

    expect((await store.withTag('work')).map((todo) => todo.title), ['Ship it']);
    await store.db.dispose();
  });

  test('stores a note with its date', () async {
    final store = TodoStore();
    await store.db.open();
    final saved = await store.add(sample('Ship it'));

    await store.addNote(Note(todoId: saved.id!, body: 'call Ana', writtenOn: const Date(year: 2026, month: 1, day: 9)));

    expect((await store.notesOf(saved.id!)).single.writtenOn, const Date(year: 2026, month: 1, day: 9));
    await store.db.dispose();
  });

  test('upserting a tag keeps the links that point at it', () async {
    final store = TodoStore();
    await store.db.open();
    final saved = await store.add(sample('Ship it'));
    final tag = await store.tag(saved.id!, 'work');
    expect(await store.tagLinks(), 1);

    await store.upsertTag(Tag(id: tag.id, name: 'renamed'));

    expect(await store.tagLinks(), 1);
    await store.db.dispose();
  });
}
