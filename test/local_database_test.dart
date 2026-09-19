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
//
// A schema-validation check, not a unit test: it opens a real, temporary
// SQLite file through `sqflite_common_ffi` to prove LocalDatabase's own
// pass-through to insert/query/update/delete/transaction/batch actually
// round-trips against real SQL, something no in-memory fake can catch. Kept
// in its own file, outside the fakes-only suite discipline the rest of
// pylon's tests hold — the same reason test/sqflite_sync_schema_test.dart is
// separate.

import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:fiber_pylon/fiber_pylon.dart' hide Database;
import 'package:fiber_pylon/src/sdk/clients/local/database/engine/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

final class Todo extends Equatable implements Storable {
  const Todo({this.id, required this.title, required this.done});

  final int? id;
  final String title;
  final bool done;

  static Todo fromRow(RawRow row) =>
      Todo(id: row['id']!.asInt, title: row['title']!.asString, done: row['done']!.asBoolean);

  Todo copyWith({int? id, String? title, bool? done}) =>
      Todo(id: id ?? this.id, title: title ?? this.title, done: done ?? this.done);

  @override
  RawRow toRow() => {'title': Value.varchar(title), 'done': Value.boolean(done)};

  @override
  List<Object?> get props => [id, title, done];
}

Future<void> _createTodos(Database db, int version) => db.execute(
  'CREATE TABLE todos ('
  'id INTEGER PRIMARY KEY AUTOINCREMENT, '
  'title TEXT NOT NULL, '
  'done INTEGER NOT NULL DEFAULT 0'
  ')',
);

Future<void> _createUniqueTodos(Database db, int version) => db.execute(
  'CREATE TABLE todos ('
  'id INTEGER PRIMARY KEY AUTOINCREMENT, '
  'title TEXT NOT NULL UNIQUE, '
  'done INTEGER NOT NULL DEFAULT 0'
  ')',
);

Future<void> _createKeywordColumns(Database db, int version) =>
    db.execute('CREATE TABLE things ("group" TEXT NOT NULL, "order" INTEGER NOT NULL)');

Future<void> _createNotes(Database db, int version) =>
    db.execute('CREATE TABLE notes (id INTEGER PRIMARY KEY AUTOINCREMENT, body TEXT)');

Future<void> _createSlots(Database db, int version) =>
    db.execute('CREATE TABLE slots (id INTEGER PRIMARY KEY AUTOINCREMENT, at)');

void main() {
  late Directory directory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pylon_local_database');
    databaseFactoryFfi.setDatabasesPath(directory.path);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  group('LocalDatabase', () {
    test('creates its table through onCreate and inserts a row', () async {
      final db = LocalDatabase(name: 'todos.db', onCreate: _createTodos);
      await db.open();

      final id = await db.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'Ship it', done: false)));

      final rows = await db.query<Todo>((q) => q.from('todos').map(Todo.fromRow));
      expect(rows, [Todo(id: id, title: 'Ship it', done: false)]);
      await db.dispose();
    });

    test('filters with where', () async {
      final db = LocalDatabase(name: 'todos_filter.db', onCreate: _createTodos);
      await db.open();
      await db.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'Done already', done: true)));
      await db.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'Still open', done: false)));

      final open = await db.query<Todo>(
        (q) => q
            .from('todos')
            .where((w) => w.isEqualTo(key: 'done', value: Value.boolean(false)))
            .map(Todo.fromRow),
      );

      expect(open.map((todo) => todo.title), ['Still open']);
      await db.dispose();
    });

    test('orders, limits and offsets', () async {
      final db = LocalDatabase(name: 'todos_order.db', onCreate: _createTodos);
      await db.open();
      await db.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'B', done: false)));
      await db.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'C', done: false)));
      await db.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'A', done: false)));

      final page = await db.query<Todo>(
        (q) => q.from('todos').orderBy(const [Sort.named('title')]).limit(1).offset(1).map(Todo.fromRow),
      );

      expect(page.map((todo) => todo.title), ['B']);
      await db.dispose();
    });

    test('orders by several terms, each in its own direction', () async {
      final db = LocalDatabase(name: 'todos_order_terms.db', onCreate: _createTodos);
      await db.open();
      await db.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'B', done: false)));
      await db.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'A', done: true)));
      await db.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'C', done: false)));

      final rows = await db.query<Todo>(
        (q) => q
            .from('todos')
            .orderBy(const [Sort.named('done'), Sort.named('title', order: SortOrder.desc)])
            .map(Todo.fromRow),
      );

      expect(rows.map((todo) => todo.title), ['C', 'B', 'A']);
      await db.dispose();
    });

    test('orders by a raw expression when a bare column cannot say it', () async {
      final db = LocalDatabase(name: 'todos_order_expression.db', onCreate: _createTodos);
      await db.open();
      await db.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'b', done: false)));
      await db.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'A', done: false)));
      await db.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'C', done: false)));

      final rows = await db.query<Todo>(
        (q) => q.from('todos').orderBy(const [Sort.expression('lower(title)')]).map(Todo.fromRow),
      );

      expect(rows.map((todo) => todo.title), ['A', 'b', 'C']);
      await db.dispose();
    });

    test('quotes the column names of select, groupBy and orderBy, so a keyword is still a column', () async {
      final db = LocalDatabase(name: 'things_keywords.db', onCreate: _createKeywordColumns);
      await db.open();
      await db.execute('INSERT INTO things ("group", "order") VALUES (?, ?)', const [
        Value.varchar('x'),
        Value.integer(1),
      ]);
      await db.execute('INSERT INTO things ("group", "order") VALUES (?, ?)', const [
        Value.varchar('y'),
        Value.integer(2),
      ]);
      await db.execute('INSERT INTO things ("group", "order") VALUES (?, ?)', const [
        Value.varchar('x'),
        Value.integer(3),
      ]);

      final groups = await db.query<String>(
        (q) => q
            .from('things')
            .select(const ['group'])
            .groupBy(const ['group'])
            .orderBy(const [Sort.named('group', order: SortOrder.desc)])
            .map((row) => row['group']!.asString),
      );

      expect(groups, ['y', 'x']);
      await db.dispose();
    });

    test('having keeps only the groups its filter matches, with its arguments bound after where', () async {
      final db = LocalDatabase(name: 'todos_having.db', onCreate: _createTodos);
      await db.open();
      for (final title in ['A', 'A', 'A', 'B', 'B', 'C']) {
        await db.insert<Todo>((i) => i.into('todos').values(Todo(title: title, done: false)));
      }

      final repeated = await db.query<String>(
        (q) => q
            .from('todos')
            .select(const ['title'])
            .where((w) => w.isNotEqualTo(key: 'title', value: const Value.varchar('B')))
            .groupBy(const ['title'])
            .having((h) => h.raw('COUNT(*) > ?', const [Value.integer(1)]))
            .map((row) => row['title']!.asString),
      );

      expect(repeated, ['A']);
      await db.dispose();
    });

    test('limit and offset refuse a negative count, which SQLite would read as no limit', () async {
      final db = LocalDatabase(name: 'todos_negative_page.db', onCreate: _createTodos);
      await db.open();

      await expectLater(db.query<Todo>((q) => q.from('todos').limit(-1).map(Todo.fromRow)), throwsRangeError);
      await expectLater(db.query<Todo>((q) => q.from('todos').offset(-1).map(Todo.fromRow)), throwsRangeError);
      await db.dispose();
    });

    test('select narrows the columns a row carries', () async {
      final db = LocalDatabase(name: 'todos_select.db', onCreate: _createTodos);
      await db.open();
      await db.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'Ship it', done: false)));

      final rows = await db.query<String>(
        (q) => q.from('todos').select(const ['title']).map((row) => row['title']!.asString),
      );

      expect(rows, ['Ship it']);
      await db.dispose();
    });

    test('updates matching rows and answers how many changed', () async {
      final db = LocalDatabase(name: 'todos_update.db', onCreate: _createTodos);
      await db.open();
      final id = await db.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'Ship it', done: false)));

      final changed = await db.update<Todo>(
        (u) => u
            .table('todos')
            .set(const Todo(title: 'Ship it', done: true))
            .where((w) => w.isEqualTo(key: 'id', value: Value.integer(id))),
      );

      expect(changed, 1);
      final rows = await db.query<Todo>(
        (q) => q.from('todos').where((w) => w.isEqualTo(key: 'id', value: Value.integer(id))).map(Todo.fromRow),
      );
      expect(rows.single.done, isTrue);
      await db.dispose();
    });

    test('deletes matching rows and answers how many were removed', () async {
      final db = LocalDatabase(name: 'todos_delete.db', onCreate: _createTodos);
      await db.open();
      await db.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'Done already', done: true)));
      final keep = await db.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'Still open', done: false)));

      final removed = await db.delete(
        (d) => d.from('todos').where((w) => w.isEqualTo(key: 'done', value: Value.boolean(true))),
      );

      expect(removed, 1);
      final rows = await db.query<Todo>((q) => q.from('todos').map(Todo.fromRow));
      expect(rows.single.id, keep);
      await db.dispose();
    });

    test('rolls back every write in a transaction that throws', () async {
      final db = LocalDatabase(name: 'todos_txn.db', onCreate: _createTodos);
      await db.open();

      await expectLater(
        db.transaction((txn) async {
          await txn.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'Never lands', done: false)));
          throw StateError('rollback');
        }),
        throwsStateError,
      );

      expect(await db.query<Todo>((q) => q.from('todos').map(Todo.fromRow)), isEmpty);
      await db.dispose();
    });

    test('commits every write made through a transaction', () async {
      final db = LocalDatabase(name: 'todos_txn_commit.db', onCreate: _createTodos);
      await db.open();

      await db.transaction((txn) async {
        await txn.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'Ship it', done: false)));
      });

      expect(await db.query<Todo>((q) => q.from('todos').map(Todo.fromRow)), hasLength(1));
      await db.dispose();
    });

    test('runs raw SQL through execute and rawQuery', () async {
      final db = LocalDatabase(name: 'todos_raw.db', onCreate: _createTodos);
      await db.open();
      await db.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'Ship it', done: false)));

      final rows = await db.rawQuery('SELECT title FROM todos WHERE done = ?', [Value.boolean(false)]);

      expect(rows, [
        const {'title': Value.varchar('Ship it')},
      ]);
      await db.dispose();
    });

    test('preserves data across a reopen', () async {
      final db = LocalDatabase(name: 'todos_reopen.db', onCreate: _createTodos);
      await db.open();
      await db.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'Ship it', done: false)));
      await db.dispose();

      final reopened = LocalDatabase(name: 'todos_reopen.db', onCreate: _createTodos);
      await reopened.open();

      final rows = await reopened.query<Todo>((q) => q.from('todos').map(Todo.fromRow));
      expect(rows.single.title, 'Ship it');
      await reopened.dispose();
    });

    test('throws when used before open', () {
      final db = LocalDatabase(name: 'todos_unopened.db', onCreate: _createTodos);

      expect(() => db.query<Todo>((q) => q.from('todos').map(Todo.fromRow)), throwsStateError);
    });

    test('throws when a query builder never calls map', () async {
      final db = LocalDatabase(name: 'todos_no_map.db', onCreate: _createTodos);
      await db.open();

      expect(() => db.query<Todo>((q) => q.from('todos')), throwsStateError);
      await db.dispose();
    });

    test('runs every queued write through a batch', () async {
      final db = LocalDatabase(name: 'todos_batch.db', onCreate: _createTodos);
      await db.open();

      final batch = db.batch();
      batch.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'First', done: false)));
      batch.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'Second', done: false)));
      await batch.commit();

      expect(await db.query<Todo>((q) => q.from('todos').map(Todo.fromRow)), hasLength(2));
      await db.dispose();
    });

    test('answers one typed result per queued statement, in the order they were queued', () async {
      final db = LocalDatabase(name: 'todos_batch_results.db', onCreate: _createUniqueTodos);
      await db.open();

      final batch = db.batch();
      batch.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'First', done: false)));
      batch.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'Second', done: false)));
      batch.update<Todo>(
        (u) => u
            .table('todos')
            .set(const Todo(title: 'First', done: true))
            .where((w) => w.isEqualTo(key: 'title', value: const Value.varchar('First'))),
      );
      batch.delete(
        (d) => d.from('todos').where((w) => w.isEqualTo(key: 'title', value: const Value.varchar('Nothing'))),
      );
      batch.execute('SELECT 1');
      batch.query((q) => q.from('todos').where((w) => w.isEqualTo(key: 'done', value: Value.boolean(true))));

      final results = await batch.commit();

      expect(results, [
        const BatchInserted(1),
        const BatchInserted(2),
        const BatchChanged(1),
        const BatchChanged(0),
        const BatchExecuted(),
        const BatchRows([
          {'id': Integer(1), 'title': Varchar('First'), 'done': Integer(1)},
        ]),
      ]);
      await db.dispose();
    });

    test('reports a statement that failed under continueOnError as a value at its own position', () async {
      final db = LocalDatabase(name: 'todos_batch_failure.db', onCreate: _createUniqueTodos);
      await db.open();

      final batch = db.batch();
      batch.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'Same', done: false)));
      batch.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'Same', done: false)));
      batch.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'Other', done: false)));

      final results = await batch.commit(continueOnError: true);

      expect(results, hasLength(3));
      expect(results[0], const BatchInserted(1));
      expect(
        results[1],
        isA<BatchFailed>().having((failed) => failed.error, 'error', isA<UniqueConstraintError>()),
      );
      expect(results[2], const BatchInserted(2));
      await db.dispose();
    });

    test('reports an insert skipped by ConflictAlgorithm.ignore as a null row id', () async {
      final db = LocalDatabase(name: 'todos_batch_ignore.db', onCreate: _createUniqueTodos);
      await db.open();
      await db.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'Same', done: false)));

      final batch = db.batch();
      batch.insert<Todo>(
        (i) => i.into('todos').values(const Todo(title: 'Same', done: false)).onConflict(ConflictAlgorithm.ignore),
      );

      expect(await batch.commit(), [const BatchInserted(null)]);
      await db.dispose();
    });

    test('answers no results at all when noResult asks to skip them', () async {
      final db = LocalDatabase(name: 'todos_batch_no_result.db', onCreate: _createUniqueTodos);
      await db.open();

      final batch = db.batch();
      batch.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'Quiet', done: false)));

      expect(await batch.commit(noResult: true), isEmpty);
      expect(await db.query<Todo>((q) => q.from('todos').map(Todo.fromRow)), hasLength(1));
      await db.dispose();
    });

    test('rolls back a whole batch when a statement fails and continueOnError is off', () async {
      final db = LocalDatabase(name: 'todos_batch_rollback.db', onCreate: _createUniqueTodos);
      await db.open();

      final batch = db.batch();
      batch.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'Same', done: false)));
      batch.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'Same', done: false)));

      await expectLater(batch.commit(), throwsA(isA<UniqueConstraintError>()));
      expect(await db.query<Todo>((q) => q.from('todos').map(Todo.fromRow)), isEmpty);
      await db.dispose();
    });

    test('reports a unique constraint violation as UniqueConstraintError', () async {
      final db = LocalDatabase(
        name: 'todos_unique.db',
        onCreate: (db, version) =>
            db.execute('CREATE TABLE todos (id INTEGER PRIMARY KEY, title TEXT NOT NULL UNIQUE)'),
      );
      await db.open();
      await db.execute('INSERT INTO todos (id, title) VALUES (1, ?)', const [Value.varchar('Ship it')]);

      await expectLater(
        db.execute('INSERT INTO todos (id, title) VALUES (2, ?)', const [Value.varchar('Ship it')]),
        throwsA(isA<UniqueConstraintError>()),
      );
      await db.dispose();
    });

    test('reports a query against a missing table as NoSuchTableError', () async {
      final db = LocalDatabase(name: 'todos_missing.db', onCreate: _createTodos);
      await db.open();

      await expectLater(
        db.query<Todo>((q) => q.from('ghosts').map(Todo.fromRow)),
        throwsA(isA<NoSuchTableError>()),
      );
      await db.dispose();
    });

    test('tableExists and tableNames read the schema back', () async {
      final db = LocalDatabase(name: 'todos_schema.db', onCreate: _createTodos);
      await db.open();

      expect(await db.tableExists('todos'), isTrue);
      expect(await db.tableExists('ghosts'), isFalse);
      expect(await db.tableNames(), ['todos']);
      await db.dispose();
    });

    test('columns reads every column PRAGMA table_info reports', () async {
      final db = LocalDatabase(name: 'todos_columns.db', onCreate: _createTodos);
      await db.open();

      final columns = await db.columns('todos');

      expect(columns, [
        const ColumnInfo(name: 'id', declaredType: 'INTEGER', isNotNull: false, primaryKeyPosition: 1),
        const ColumnInfo(name: 'title', declaredType: 'TEXT', isNotNull: true, primaryKeyPosition: 0),
        const ColumnInfo(
          name: 'done',
          declaredType: 'INTEGER',
          isNotNull: true,
          primaryKeyPosition: 0,
          defaultSql: '0',
        ),
      ]);
      await db.dispose();
    });
  });

  group('FilterBuilder', () {
    late LocalDatabase db;

    setUp(() async {
      db = LocalDatabase(name: 'todos_filters.db', onCreate: _createTodos);
      await db.open();
      await db.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'Ant', done: false)));
      await db.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'Bee', done: true)));
      await db.insert<Todo>((i) => i.into('todos').values(const Todo(title: 'Cat', done: true)));
    });

    tearDown(() => db.dispose());

    Future<List<String>> titlesWhere(Filter Function(FilterBuilder w) build) async {
      final rows = await db.query<Todo>(
        (q) => q.from('todos').where(build).orderBy(const [Sort.named('title')]).map(Todo.fromRow),
      );
      return rows.map((todo) => todo.title).toList();
    }

    test('isNotEqualTo excludes the matching rows', () async {
      expect(await titlesWhere((w) => w.isNotEqualTo(key: 'title', value: const Value.varchar('Bee'))), [
        'Ant',
        'Cat',
      ]);
    });

    test('isGreaterThan and isLessThan compare ids', () async {
      final all = await db.query<Todo>(
        (q) => q.from('todos').orderBy(const [Sort.named('id')]).map(Todo.fromRow),
      );
      final firstId = all.first.id!;

      expect(await titlesWhere((w) => w.isGreaterThan(key: 'id', value: Value.integer(firstId))), [
        'Bee',
        'Cat',
      ]);
      expect(await titlesWhere((w) => w.isLessThan(key: 'id', value: Value.integer(firstId))), isEmpty);
    });

    test('isGreaterThanOrEqualTo and isLessThanOrEqualTo include the boundary', () async {
      final all = await db.query<Todo>(
        (q) => q.from('todos').orderBy(const [Sort.named('id')]).map(Todo.fromRow),
      );
      final firstId = all.first.id!;

      expect(await titlesWhere((w) => w.isGreaterThanOrEqualTo(key: 'id', value: Value.integer(firstId))), [
        'Ant',
        'Bee',
        'Cat',
      ]);
      expect(await titlesWhere((w) => w.isLessThanOrEqualTo(key: 'id', value: Value.integer(firstId))), ['Ant']);
    });

    test('isLike matches a pattern', () async {
      expect(await titlesWhere((w) => w.isLike(key: 'title', pattern: 'B%')), ['Bee']);
    });

    test('isIn matches any of a set of values', () async {
      expect(
        await titlesWhere(
          (w) => w.isIn(key: 'title', values: const [Value.varchar('Ant'), Value.varchar('Cat')]),
        ),
        ['Ant', 'Cat'],
      );
    });

    test('isIn with no values matches nothing', () async {
      expect(await titlesWhere((w) => w.isIn(key: 'title', values: const [])), isEmpty);
    });

    test('isNull and isNotNull read column presence', () async {
      expect(await titlesWhere((w) => w.isNull('title')), isEmpty);
      expect(await titlesWhere((w) => w.isNotNull('title')), ['Ant', 'Bee', 'Cat']);
    });

    test('and combines every condition', () async {
      expect(
        await titlesWhere(
          (w) => w.and([
            w.isEqualTo(key: 'done', value: Value.boolean(true)),
            w.isLike(key: 'title', pattern: 'B%'),
          ]),
        ),
        ['Bee'],
      );
    });

    test('or matches any condition', () async {
      expect(
        await titlesWhere(
          (w) => w.or([
            w.isEqualTo(key: 'title', value: const Value.varchar('Ant')),
            w.isEqualTo(key: 'title', value: const Value.varchar('Cat')),
          ]),
        ),
        ['Ant', 'Cat'],
      );
    });

    test('not negates a condition', () async {
      expect(await titlesWhere((w) => w.not(w.isEqualTo(key: 'done', value: Value.boolean(true)))), ['Ant']);
    });

    test('raw carries a predicate the rest of the builder cannot express', () async {
      expect(await titlesWhere((w) => w.raw('length(title) = ?', const [Value.integer(3)])), [
        'Ant',
        'Bee',
        'Cat',
      ]);
    });
  });
  group('FilterBuilder over nulls, text and stored conventions', () {
    late LocalDatabase notes;

    setUp(() async {
      notes = LocalDatabase(name: 'notes_filters.db', onCreate: _createNotes);
      await notes.open();
      for (final body in [
        const Value.varchar('alpha'),
        const Value.varchar('beta'),
        const Value.nil(),
      ]) {
        await notes.execute('INSERT INTO notes (body) VALUES (?)', [body]);
      }
    });

    tearDown(() => notes.dispose());

    Future<List<int>> idsWhere(Filter Function(FilterBuilder w) build) => notes.query<int>(
      (q) => q
          .from('notes')
          .select(const ['id'])
          .where(build)
          .orderBy(const [Sort.named('id')])
          .map((row) => row['id']!.asInt),
    );

    test('isEqualTo a Nil matches the rows where the column is null', () async {
      expect(await idsWhere((w) => w.isEqualTo(key: 'body', value: const Value.nil())), [3]);
    });

    test('isNotEqualTo a Nil matches the rows where the column has a value', () async {
      expect(await idsWhere((w) => w.isNotEqualTo(key: 'body', value: const Value.nil())), [1, 2]);
    });

    test('isNotEqualTo a value keeps the rows where the column is null', () async {
      expect(await idsWhere((w) => w.isNotEqualTo(key: 'body', value: const Value.varchar('alpha'))), [2, 3]);
    });

    test('not keeps the rows its filter cannot decide on', () async {
      expect(await idsWhere((w) => w.not(w.isEqualTo(key: 'body', value: const Value.varchar('alpha')))), [
        2,
        3,
      ]);
      expect(await idsWhere((w) => w.not(w.isLike(key: 'body', pattern: 'a%'))), [2, 3]);
    });

    test('isIn with a Nil among its values matches the null rows too', () async {
      expect(
        await idsWhere((w) => w.isIn(key: 'body', values: const [Value.varchar('beta'), Value.nil()])),
        [2, 3],
      );
      expect(await idsWhere((w) => w.isIn(key: 'body', values: const [Value.nil()])), [3]);
    });

    test('an ordering filter refuses a Nil, which has no order', () async {
      await expectLater(
        idsWhere((w) => w.isGreaterThan(key: 'body', value: const Value.nil())),
        throwsArgumentError,
      );
      await expectLater(
        idsWhere((w) => w.isLessThanOrEqualTo(key: 'body', value: const Value.nil())),
        throwsArgumentError,
      );
    });

    test('contains, startsWith and endsWith match the text as written', () async {
      await notes.execute('INSERT INTO notes (body) VALUES (?)', const [Value.varchar('50% off_sale\\now')]);

      expect(await idsWhere((w) => w.contains(key: 'body', text: 'lph')), [1]);
      expect(await idsWhere((w) => w.startsWith(key: 'body', text: 'be')), [2]);
      expect(await idsWhere((w) => w.endsWith(key: 'body', text: 'ta')), [2]);
      expect(await idsWhere((w) => w.contains(key: 'body', text: '50%')), [4]);
      expect(await idsWhere((w) => w.contains(key: 'body', text: '_sale')), [4]);
      expect(await idsWhere((w) => w.contains(key: 'body', text: 'e\\n')), [4]);
      expect(await idsWhere((w) => w.contains(key: 'body', text: '%')), [4]);
      expect(await idsWhere((w) => w.contains(key: 'body', text: '_')), [4]);
    });

    test('isLike still reads its pattern as a pattern', () async {
      expect(await idsWhere((w) => w.isLike(key: 'body', pattern: '%')), [1, 2]);
    });

    test('an ordering filter on stored times gives the order of the clock', () async {
      final slots = LocalDatabase(name: 'slots_filters.db', onCreate: _createSlots);
      await slots.open();
      const nine = Time(hour: 9, minute: 0);
      const nineThirty = Time(hour: 9, minute: 30, second: 5, millisecond: 250);
      const ten = Time(hour: 10, minute: 0);
      for (final time in [nine, ten, nineThirty]) {
        await slots.execute('INSERT INTO slots (at) VALUES (?)', [Value.time(time)]);
      }

      Future<List<int>> idsWhereAt(Filter Function(FilterBuilder w) build) => slots.query<int>(
        (q) => q
            .from('slots')
            .select(const ['id'])
            .where(build)
            .orderBy(const [Sort.named('id')])
            .map((row) => row['id']!.asInt),
      );

      expect(await idsWhereAt((w) => w.isGreaterThan(key: 'at', value: Value.time(nine))), [2, 3]);
      expect(await idsWhereAt((w) => w.isLessThan(key: 'at', value: Value.time(ten))), [1, 3]);
      expect(await idsWhereAt((w) => w.isEqualTo(key: 'at', value: Value.time(nineThirty))), [3]);
      await slots.dispose();
    });

    test('an equality filter on a numeric interval treats 3 and 3.0 as the same bound', () async {
      final slots = LocalDatabase(name: 'intervals_filters.db', onCreate: _createSlots);
      await slots.open();
      await slots.execute('INSERT INTO slots (at) VALUES (?)', [
        Value.interval(const IntervalBounds.num(start: 3.0, end: 4.5)),
      ]);

      final ids = await slots.query<int>(
        (q) => q
            .from('slots')
            .select(const ['id'])
            .where(
              (w) => w.isEqualTo(key: 'at', value: Value.interval(const IntervalBounds.num(start: 3, end: 4.5))),
            )
            .map((row) => row['id']!.asInt),
      );

      expect(ids, [1]);
      await slots.dispose();
    });
  });
}
