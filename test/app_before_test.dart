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
import 'package:fiber_pylon/src/sdk/clients/local/database/engine/database.dart';
import 'package:fiber_pylon/src/sdk/clients/local/database/engine/schema/schema.dart';
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

final class Todo extends Equatable implements DatabaseRecord {
  const Todo({this.id, required this.title, this.done = false, required this.status, required this.priority, this.due});

  final int? id;
  final String title;
  final bool done;
  final Status status;
  final Priority priority;
  final Date? due;

  static Todo fromRow(DatabaseRow row) => Todo(
    id: row['id']!.asInt,
    title: row['title']!.asString,
    done: row['done']!.asBoolean,
    status: row['status']!.asEnum(Status.values),
    priority: priorityJson.decode(row['priority']!),
    due: row['due']! is Nil ? null : row['due']!.asDate,
  );

  @override
  DatabaseRow toRow() => {
    'title': DatabaseType.varchar(title),
    'done': DatabaseType.boolean(done),
    'status': DatabaseType.enum_(status),
    'priority': priorityJson.encode(priority),
    'due': due == null ? const DatabaseType.nil() : DatabaseType.date(due!),
  };

  @override
  List<Object?> get props => [id, title, done, status, priority.level, priority.label, due];
}

final class DonePatch implements DatabaseRecord {
  const DonePatch(this.done);
  final bool done;

  @override
  DatabaseRow toRow() => {'done': DatabaseType.boolean(done)};
}

final class Tag extends Equatable implements DatabaseRecord {
  const Tag({required this.id, required this.name});

  final UuidValue id;
  final String name;

  static Tag fromRow(DatabaseRow row) => Tag(id: row['id']!.asUuid, name: row['name']!.asString);

  @override
  DatabaseRow toRow() => {'id': DatabaseType.uuid(id), 'name': DatabaseType.varchar(name)};

  @override
  List<Object?> get props => [id, name];
}

final class TodoTag implements DatabaseRecord {
  const TodoTag({required this.todoId, required this.tagId});

  final int todoId;
  final UuidValue tagId;

  @override
  DatabaseRow toRow() => {'todo_id': DatabaseType.integer(todoId), 'tag_id': DatabaseType.uuid(tagId)};
}

final class Note extends Equatable implements DatabaseRecord {
  const Note({this.id, required this.todoId, required this.body, required this.writtenOn});

  final int? id;
  final int todoId;
  final String body;
  final Date writtenOn;

  static Note fromRow(DatabaseRow row) => Note(
    id: row['id']!.asInt,
    todoId: row['todo_id']!.asInt,
    body: row['body']!.asString,
    writtenOn: row['written_on']!.asDate,
  );

  @override
  DatabaseRow toRow() => {
    'todo_id': DatabaseType.integer(todoId),
    'body': DatabaseType.varchar(body),
    'written_on': DatabaseType.date(writtenOn),
  };

  @override
  List<Object?> get props => [id, todoId, body, writtenOn];
}

final DeclaredTable todosTable = TableBuilder('todos').columns(
  (c) => {
    'id': c.integer().isPrimary().autoincrement(),
    'title': c.text().isNullable(false),
    'done': c.integer().isNullable(false).default_(DatabaseType.boolean(false)),
    'status': c.text().isNullable(false),
    'priority': c.text().isNullable(false),
    'due': c.integer(),
  },
);

final DeclaredTable tagsTable = TableBuilder(
  'tags',
).columns((c) => {'id': c.text().isPrimary(), 'name': c.text().isNullable(false).unique()});

final DeclaredTable todoTagsTable = TableBuilder('todo_tags')
    .primaryKey((pk) => pk.columns(const ['todo_id', 'tag_id']))
    .columns(
      (c) => {
        'todo_id': c
            .integer()
            .isNullable(false)
            .references(const ColumnReference(table: 'todos', column: 'id', onDelete: ReferentialAction.cascade)),
        'tag_id': c
            .text()
            .isNullable(false)
            .references(const ColumnReference(table: 'tags', column: 'id', onDelete: ReferentialAction.cascade)),
      },
    );

final DeclaredTable notesTable = TableBuilder('notes').columns(
  (c) => {
    'id': c.integer().isPrimary().autoincrement(),
    'todo_id': c
        .integer()
        .isNullable(false)
        .references(const ColumnReference(table: 'todos', column: 'id', onDelete: ReferentialAction.cascade)),
    'body': c.text().isNullable(false),
    'written_on': c.integer().isNullable(false),
  },
);

Future<void> _create(Database db, int version) async {
  for (final table in [todosTable, tagsTable, todoTagsTable, notesTable]) {
    for (final statement in table.statements) {
      await db.execute(statement);
    }
  }
}

final class TodoStore {
  TodoStore({required int version})
    : db = LocalDatabase(
        name: 'app.db',
        version: version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _create,
        onUpgrade: (db, from, to) async {
          if (from < 2) await db.execute('ALTER TABLE todos ADD COLUMN due INTEGER');
        },
      );

  final LocalDatabase db;

  Future<void> open() => db.open();

  Future<int> add(Todo todo) => db.insert<Todo>((i) => i.into('todos').values(todo));

  Future<Todo?> getById(int id) async {
    final rows = await db.query<Todo>(
      (q) => q
          .from('todos')
          .where((w) => w.isEqualTo(key: 'id', value: DatabaseType.integer(id)))
          .limit(1)
          .map(Todo.fromRow),
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Todo>> page({required Status status, required int page, required int size}) => db.query<Todo>(
    (q) => q
        .from('todos')
        .where(
          (w) => w.and([
            w.isEqualTo(key: 'status', value: DatabaseType.enum_(status)),
            w.isEqualTo(key: 'done', value: DatabaseType.boolean(false)),
          ]),
        )
        .orderBy(const [DatabaseOrder.named('title')])
        .limit(size)
        .offset(page * size)
        .map(Todo.fromRow),
  );

  Future<int> markDone(int id) => db.update<DonePatch>(
    (u) => u
        .table('todos')
        .set(const DonePatch(true))
        .where((w) => w.isEqualTo(key: 'id', value: DatabaseType.integer(id))),
  );

  Future<int> upsertTag(Tag tag) async {
    await db.insert<Tag>((i) => i.into('tags').values(tag).onConflict(ConflictAlgorithm.replace));
    return 1;
  }

  Future<int> delete(int id) =>
      db.delete((d) => d.from('todos').where((w) => w.isEqualTo(key: 'id', value: DatabaseType.integer(id))));

  Future<int> countOpen() async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM todos WHERE done = ?', [DatabaseType.boolean(false)]);
    return rows.single['n']!.asInt;
  }

  Future<bool> exists(int id) async {
    final rows = await db.rawQuery('SELECT 1 AS present FROM todos WHERE id = ? LIMIT 1', [DatabaseType.integer(id)]);
    return rows.isNotEmpty;
  }

  Future<void> tag(int todoId, Tag tag) => db.transaction((txn) async {
    await txn.insert<Tag>((i) => i.into('tags').values(tag));
    await txn.insert<TodoTag>((i) => i.into('todo_tags').values(TodoTag(todoId: todoId, tagId: tag.id)));
  });

  Future<List<Todo>> withTag(String name) async {
    final rows = await db.rawQuery(
      'SELECT todos.* FROM todos JOIN todo_tags ON todo_tags.todo_id = todos.id '
      'JOIN tags ON tags.id = todo_tags.tag_id WHERE tags.name = ?',
      [DatabaseType.varchar(name)],
    );
    return rows.map(Todo.fromRow).toList();
  }

  Future<List<int>> addAll(List<Todo> todos) async {
    final batch = db.batch();
    for (final todo in todos) {
      batch.insert<Todo>((i) => i.into('todos').values(todo));
    }
    final results = await batch.commit();
    return [for (final result in results) (result as DatabaseBatchInserted).rowId!];
  }

  Future<void> addNote(Note note) => db.insert<Note>((i) => i.into('notes').values(note));

  Future<List<Note>> notesOf(int todoId) => db.query<Note>(
    (q) => q
        .from('notes')
        .where((w) => w.isEqualTo(key: 'todo_id', value: DatabaseType.integer(todoId)))
        .map(Note.fromRow),
  );

  Future<int> tagLinks() async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM todo_tags');
    return rows.single['n']!.asInt;
  }
}

void main() {
  late Directory directory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pylon_before_app');
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
    final store = TodoStore(version: 2);
    await store.open();
    final id = await store.add(sample('Ship it'));

    final found = await store.getById(id);

    expect(found?.title, 'Ship it');
    expect(found?.priority.label, 'normal');
    expect(found?.due, isNull);
    await store.db.dispose();
  });

  test('a version 1 file gains its due column through the version 2 migration', () async {
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
      const DatabaseType.varchar('Old'),
      DatabaseType.boolean(false),
      DatabaseType.enum_(Status.open),
      priorityJson.encode(const Priority(level: 1, label: 'low')),
    ]);
    await v1.dispose();
    final id = 1;

    final v2 = TodoStore(version: 2);
    await v2.open();

    final found = await v2.getById(id);
    expect(found?.title, 'Old');
    expect(found?.due, isNull);
    await v2.db.dispose();
  });

  test('lists a page of open todos, marks one done, counts, checks and deletes', () async {
    final store = TodoStore(version: 2);
    await store.open();
    final ids = await store.addAll([
      sample('C'),
      sample('A', due: const Date(year: 2026, month: 5, day: 4)),
      sample('B'),
      sample('D', status: Status.doing),
    ]);

    final first = await store.page(status: Status.open, page: 0, size: 2);
    expect(first.map((todo) => todo.title), ['A', 'B']);
    expect(first.first.due, const Date(year: 2026, month: 5, day: 4));

    expect(await store.markDone(ids[1]), 1);
    expect(await store.countOpen(), 3);
    expect(await store.exists(ids[1]), isTrue);
    expect(await store.delete(ids[1]), 1);
    expect(await store.exists(ids[1]), isFalse);
    await store.db.dispose();
  });

  test('tags a todo in one transaction and lists the todos of a tag', () async {
    final store = TodoStore(version: 2);
    await store.open();
    final id = await store.add(sample('Ship it'));
    final tag = Tag(id: UuidValue.fromString(const Uuid().v4()), name: 'work');

    await store.tag(id, tag);

    expect((await store.withTag('work')).map((todo) => todo.title), ['Ship it']);
    await store.db.dispose();
  });

  test('stores a note with its date', () async {
    final store = TodoStore(version: 2);
    await store.open();
    final id = await store.add(sample('Ship it'));

    await store.addNote(Note(todoId: id, body: 'call Ana', writtenOn: const Date(year: 2026, month: 1, day: 9)));

    expect((await store.notesOf(id)).single.writtenOn, const Date(year: 2026, month: 1, day: 9));
    await store.db.dispose();
  });

  test('upserting a tag through replace silently deletes the links that point at it', () async {
    final store = TodoStore(version: 2);
    await store.open();
    final id = await store.add(sample('Ship it'));
    final tag = Tag(id: UuidValue.fromString(const Uuid().v4()), name: 'work');
    await store.tag(id, tag);
    expect(await store.tagLinks(), 1);

    await store.upsertTag(Tag(id: tag.id, name: 'renamed'));

    expect(await store.tagLinks(), 0, reason: 'REPLACE deletes the tag row, so ON DELETE CASCADE removed the link');
    await store.db.dispose();
  });
}
