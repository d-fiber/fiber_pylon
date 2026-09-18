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

import 'package:fiber_pylon/fiber_pylon.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

void main() {
  group('TableBuilder (rendering)', () {
    test('renders a single-column primary key inline', () {
      final table = TableBuilder(
        'todos',
      ).columns((c) => {'id': c.integer().isPrimary().autoincrement(), 'title': c.text().isNullable(false)});

      expect(table.statements, [
        'CREATE TABLE "todos" ("id" INTEGER PRIMARY KEY AUTOINCREMENT, "title" TEXT NOT NULL)',
      ]);
    });

    test('renders a composite primary key at the table level', () {
      final table = TableBuilder('memberships')
          .primaryKey((pk) => pk.columns(['account_id', 'group_id']))
          .columns((c) => {'account_id': c.integer(), 'group_id': c.integer()});

      expect(table.statements, [
        'CREATE TABLE "memberships" ("account_id" INTEGER, "group_id" INTEGER, '
            'PRIMARY KEY ("account_id", "group_id"))',
      ]);
    });

    test('throws when a composite primary key collides with a column-level one', () {
      final builder = TableBuilder('bad').primaryKey((pk) => pk.columns(['a']));

      expect(() => builder.columns((c) => {'a': c.integer().isPrimary()}), throwsArgumentError);
    });

    test('renders unique, check and foreign key table constraints', () {
      final table = TableBuilder('devices')
          .uniques(
            (u) => [
              u.columns(['account_id', 'device_id']).name('devices_account_device_key'),
            ],
          )
          .checks((ck) => [ck.expression('last_seen_at <= unixepoch()')])
          .foreignKeys(
            (fk) => [
              fk.columns(['account_id']).references('accounts').onDelete(ReferentialAction.cascade),
            ],
          )
          .columns(
            (c) => {
              'account_id': c.integer().isNullable(false),
              'device_id': c.text().isNullable(false),
              'last_seen_at': c.integer().isNullable(false),
            },
          );

      expect(table.statements, [
        'CREATE TABLE "devices" ('
            '"account_id" INTEGER NOT NULL, '
            '"device_id" TEXT NOT NULL, '
            '"last_seen_at" INTEGER NOT NULL, '
            'CONSTRAINT "devices_account_device_key" UNIQUE ("account_id", "device_id"), '
            'CHECK (last_seen_at <= unixepoch()), '
            'FOREIGN KEY ("account_id") REFERENCES "accounts" ON DELETE CASCADE'
            ')',
      ]);
    });

    test('renders a column-level foreign key reference', () {
      final table = TableBuilder('devices').columns(
        (c) => {
          'id': c.integer().isPrimary(),
          'account_id': c.integer().references(
            const ColumnReference(table: 'accounts', onDelete: ReferentialAction.cascade),
          ),
        },
      );

      expect(table.statements, [
        'CREATE TABLE "devices" ('
            '"id" INTEGER PRIMARY KEY, '
            '"account_id" INTEGER REFERENCES "accounts" ON DELETE CASCADE'
            ')',
      ]);
    });

    test('renders STRICT and WITHOUT ROWID', () {
      final table = TableBuilder(
        'kv',
      ).strict().withoutRowid().columns((c) => {'key': c.text().isPrimary(), 'value': c.any()});

      expect(table.statements, ['CREATE TABLE "kv" ("key" TEXT PRIMARY KEY, "value" ANY) STRICT, WITHOUT ROWID']);
    });

    test('renders a generated column', () {
      final table = TableBuilder('people').columns(
        (c) => {
          'first': c.text(),
          'last': c.text(),
          'full': c.text().generated(
            const GeneratedColumn(expression: "first || ' ' || last", storage: GeneratedStorage.virtual),
          ),
        },
      );

      expect(table.statements, [
        'CREATE TABLE "people" ('
            '"first" TEXT, '
            '"last" TEXT, '
            '"full" TEXT GENERATED ALWAYS AS (first || \' \' || last) VIRTUAL'
            ')',
      ]);
    });

    test('renders one CREATE INDEX per declared index, after the table', () {
      final table = TableBuilder('todos')
          .indexes(
            (i) => [
              i.name('todos_done_idx').columns(['done']),
              i
                  .name('todos_title_idx')
                  .columns([const IndexColumn('title', collation: 'NOCASE', order: IndexOrder.desc)])
                  .where('done = 0'),
            ],
          )
          .columns((c) => {'title': c.text(), 'done': c.integer()});

      expect(table.statements, [
        'CREATE TABLE "todos" ("title" TEXT, "done" INTEGER)',
        'CREATE INDEX "todos_done_idx" ON "todos" (done)',
        'CREATE INDEX "todos_title_idx" ON "todos" (title COLLATE NOCASE DESC) WHERE done = 0',
      ]);
    });

    test('throws when an index builder never names its columns', () {
      expect(() => TableBuilder('todos').indexes((i) => [i.name('todos_idx')]), throwsStateError);
    });

    test('throws when a foreign key builder never names what it references', () {
      expect(
        () => TableBuilder('devices').foreignKeys(
          (fk) => [
            fk.columns(['account_id']),
          ],
        ),
        throwsStateError,
      );
    });
  });

  group('TableBuilder (against a real database)', () {
    late Directory directory;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('pylon_schema');
      databaseFactoryFfi.setDatabasesPath(directory.path);
    });

    tearDown(() async {
      await directory.delete(recursive: true);
    });

    test('a declared table actually creates and accepts rows', () async {
      final declared = TableBuilder('todos')
          .checks((ck) => [ck.expression("length(title) > 0")])
          .indexes(
            (i) => [
              i.name('todos_done_idx').columns(['done']),
            ],
          )
          .columns(
            (c) => {
              'id': c.integer().isPrimary().autoincrement(),
              'title': c.text().isNullable(false),
              'done': c.integer().isNullable(false).default_('0'),
            },
          );

      final db = LocalDatabase(
        name: 'schema_todos.db',
        onCreate: (db, version) async {
          for (final statement in declared.statements) {
            await db.execute(statement);
          }
        },
      );
      await db.open();

      await db.execute('INSERT INTO todos (title) VALUES (?)', const [DatabaseType.varchar('Ship it')]);
      final rows = await db.rawQuery('SELECT id, title, done FROM todos');
      expect(rows, [
        const {
          'id': DatabaseType.integer(1),
          'title': DatabaseType.varchar('Ship it'),
          'done': DatabaseType.integer(0),
        },
      ]);

      expect(await db.tableNames(), ['todos']);
      final columns = await db.columns('todos');
      expect(columns.map((column) => column.name), ['id', 'title', 'done']);

      await db.dispose();
    });

    test('a CHECK constraint the DSL renders is actually enforced', () async {
      final declared = TableBuilder(
        'todos',
      ).checks((ck) => [ck.expression('length(title) > 0')]).columns((c) => {'title': c.text().isNullable(false)});

      final db = LocalDatabase(
        name: 'schema_check.db',
        onCreate: (db, version) async {
          for (final statement in declared.statements) {
            await db.execute(statement);
          }
        },
      );
      await db.open();

      await expectLater(
        db.execute('INSERT INTO todos (title) VALUES (?)', const [DatabaseType.varchar('')]),
        throwsA(isA<DatabaseError>()),
      );

      await db.dispose();
    });

    test('a STRICT table refuses a value that does not match its column type', () async {
      final declared = TableBuilder('kv').strict().columns((c) => {'key': c.text().isPrimary(), 'value': c.integer()});

      final db = LocalDatabase(
        name: 'schema_strict.db',
        onCreate: (db, version) async {
          for (final statement in declared.statements) {
            await db.execute(statement);
          }
        },
      );
      await db.open();

      await expectLater(
        db.execute('INSERT INTO kv (key, value) VALUES (?, ?)', const [
          DatabaseType.varchar('a'),
          DatabaseType.varchar('not a number'),
        ]),
        throwsA(isA<DatabaseError>()),
      );

      await db.dispose();
    });
  });
}
