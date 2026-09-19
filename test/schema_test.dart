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
import 'dart:typed_data';

import 'package:fiber_pylon/fiber_pylon.dart' hide Database;
import 'package:fiber_pylon/src/sdk/clients/local/database/engine/schema/schema.dart';
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
        'CREATE TABLE "memberships" ("account_id" INTEGER NOT NULL, "group_id" INTEGER NOT NULL, '
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

      expect(table.statements, [
        'CREATE TABLE "kv" ("key" TEXT PRIMARY KEY NOT NULL, "value" ANY) STRICT, WITHOUT ROWID',
      ]);
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
              i.name('todos_done_idx').columns(const [IndexColumn.named('done')]),
              i
                  .name('todos_title_idx')
                  .columns(const [IndexColumn.named('title', collation: Collation.noCase, order: SortOrder.desc)])
                  .where('done = 0'),
            ],
          )
          .columns((c) => {'title': c.text(), 'done': c.integer()});

      expect(table.statements, [
        'CREATE TABLE "todos" ("title" TEXT, "done" INTEGER)',
        'CREATE INDEX "todos_done_idx" ON "todos" ("done")',
        'CREATE INDEX "todos_title_idx" ON "todos" ("title" COLLATE NOCASE DESC) WHERE done = 0',
      ]);
    });

    test('renders a literal default as SQL, quoting text and spelling a blob in hexadecimal', () {
      final table = TableBuilder('samples').strict().columns(
        (c) => {
          'count': c.integer().default_(const Integer(-3)),
          'ratio': c.real().default_(const Real(0.25)),
          'label': c.text().default_(const Varchar("it's")),
          'payload': c.blob().default_(Blob(Uint8List.fromList([0, 15, 255]))),
          'anything': c.any().default_(const Value.nil()),
        },
      );

      expect(table.statements, [
        'CREATE TABLE "samples" ('
            '"count" INTEGER DEFAULT (-3), '
            '"ratio" REAL DEFAULT (0.25), '
            '"label" TEXT DEFAULT (\'it\'\'s\'), '
            '"payload" BLOB DEFAULT (X\'000fff\'), '
            '"anything" ANY DEFAULT (NULL)'
            ') STRICT',
      ]);
    });

    test('renders a boolean default as the integer the value layer stores it as', () {
      final table = TableBuilder(
        'todos',
      ).columns((c) => {'done': c.integer().isNullable(false).default_(Value.boolean(false))});

      expect(table.statements, ['CREATE TABLE "todos" ("done" INTEGER NOT NULL DEFAULT (0))']);
    });

    test('renders an expression default as written', () {
      final table = TableBuilder(
        'events',
      ).columns((c) => {'at': c.integer().defaultExpression("CAST(strftime('%s', 'now') AS INTEGER)")});

      expect(table.statements, [
        'CREATE TABLE "events" ("at" INTEGER DEFAULT (CAST(strftime(\'%s\', \'now\') AS INTEGER)))',
      ]);
    });

    test('refuses a default the SQL grammar has no literal for', () {
      expect(
        () => TableBuilder('samples').columns((c) => {'ratio': c.real().default_(const Real(double.nan))}),
        throwsArgumentError,
      );
      expect(
        () => TableBuilder('samples').columns((c) => {'ratio': c.real().default_(const Real(double.infinity))}),
        throwsArgumentError,
      );
    });

    test('renders the collation of a text column', () {
      final table = TableBuilder('people').columns(
        (c) => {
          'name': c.text().collation(Collation.noCase),
          'code': c.text().collation(Collation.rtrim),
          'raw': c.text().collation(Collation.binary),
        },
      );

      expect(table.statements, [
        'CREATE TABLE "people" ("name" TEXT COLLATE NOCASE, "code" TEXT COLLATE RTRIM, "raw" TEXT COLLATE BINARY)',
      ]);
    });

    test('keeps the modifiers of the column type after any other modifier', () {
      final table = TableBuilder('people').columns(
        (c) => {
          'id': c.integer().isNullable(false).unique().isPrimary().autoincrement(),
          'name': c.text().isNullable(false).unique().collation(Collation.noCase),
        },
      );

      expect(table.statements, [
        'CREATE TABLE "people" ("id" INTEGER PRIMARY KEY AUTOINCREMENT UNIQUE, "name" TEXT NOT NULL UNIQUE COLLATE NOCASE)',
      ]);
    });

    test('renders a deferral on a column-level and a table-level foreign key', () {
      final table = TableBuilder('devices')
          .foreignKeys(
            (fk) => [
              fk.columns(['owner_id']).references('accounts').deferrable(Deferral.initiallyDeferred),
              fk.columns(['backup_id']).references('accounts').deferrable(Deferral.initiallyImmediate),
              fk.columns(['peer_id']).references('devices'),
            ],
          )
          .columns(
            (c) => {
              'account_id': c.integer().references(
                const ColumnReference(table: 'accounts', deferral: Deferral.initiallyDeferred),
              ),
              'owner_id': c.integer(),
              'backup_id': c.integer(),
              'peer_id': c.integer(),
            },
          );

      expect(table.statements, [
        'CREATE TABLE "devices" ('
            '"account_id" INTEGER REFERENCES "accounts" DEFERRABLE INITIALLY DEFERRED, '
            '"owner_id" INTEGER, "backup_id" INTEGER, "peer_id" INTEGER, '
            'FOREIGN KEY ("owner_id") REFERENCES "accounts" DEFERRABLE INITIALLY DEFERRED, '
            'FOREIGN KEY ("backup_id") REFERENCES "accounts" DEFERRABLE, '
            'FOREIGN KEY ("peer_id") REFERENCES "devices"'
            ')',
      ]);
    });

    test('quotes an index column named like an SQL keyword and leaves an expression as written', () {
      final table = TableBuilder('people')
          .indexes(
            (i) => [
              i.name('people_group_idx').columns(const [IndexColumn.named('group')]),
              i.name('people_email_idx').columns(const [
                IndexColumn.expression('lower(email)', collation: Collation.noCase),
              ]).unique(),
            ],
          )
          .columns((c) => {'group': c.text(), 'email': c.text()});

      expect(table.statements, [
        'CREATE TABLE "people" ("group" TEXT, "email" TEXT)',
        'CREATE INDEX "people_group_idx" ON "people" ("group")',
        'CREATE UNIQUE INDEX "people_email_idx" ON "people" (lower(email) COLLATE NOCASE)',
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
              i.name('todos_done_idx').columns(const [IndexColumn.named('done')]),
            ],
          )
          .columns(
            (c) => {
              'id': c.integer().isPrimary().autoincrement(),
              'title': c.text().isNullable(false),
              'done': c.integer().isNullable(false).default_(Value.boolean(false)),
            },
          );

      final db = LocalDatabase.forTesting(
        name: 'schema_todos.db',
        onCreate: (db, version) async {
          for (final statement in declared.statements) {
            await db.execute(statement);
          }
        },
      );
      await db.open();

      await db.runSql('INSERT INTO todos (title) VALUES (?)', const [Value.varchar('Ship it')]);
      final rows = await db.runRawQuery('SELECT id, title, done FROM todos');
      expect(rows, [
        const {
          'id': Value.integer(1),
          'title': Value.varchar('Ship it'),
          'done': Value.integer(0),
        },
      ]);

      expect(await db.listTables(), ['todos']);
      final columns = await db.listColumns('todos');
      expect(columns.map((column) => column.name), ['id', 'title', 'done']);

      await db.dispose();
    });

    LocalDatabase openDeclared(String name, DeclaredTable declared, {Future<void> Function(Database)? onConfigure}) =>
        LocalDatabase.forTesting(
          name: name,
          onConfigure: onConfigure,
          onCreate: (db, version) async {
            for (final statement in declared.statements) {
              await db.execute(statement);
            }
          },
        );

    test('a typed default is applied by SQLite exactly as the value layer stores it', () async {
      final declared = TableBuilder('samples').columns(
        (c) => {
          'id': c.integer().isPrimary().autoincrement(),
          'done': c.integer().default_(Value.boolean(true)),
          'ratio': c.real().default_(const Real(0.25)),
          'label': c.text().default_(const Varchar("it's")),
          'payload': c.blob().default_(Blob(Uint8List.fromList([0, 15, 255]))),
        },
      );
      final db = openDeclared('schema_defaults.db', declared);
      await db.open();

      await db.runSql('INSERT INTO samples DEFAULT VALUES');
      final row = (await db.runRawQuery('SELECT done, ratio, label, payload FROM samples')).single;

      expect(row['done']!.asBoolean, isTrue);
      expect(row['ratio']!.asDouble, 0.25);
      expect(row['label']!.asString, "it's");
      expect(row['payload']!.asBytes, [0, 15, 255]);
      await db.dispose();
    });

    test('a NOCASE collation makes a unique column treat two spellings as one', () async {
      final declared = TableBuilder(
        'people',
      ).columns((c) => {'name': c.text().isNullable(false).unique().collation(Collation.noCase)});
      final db = openDeclared('schema_collation.db', declared);
      await db.open();
      await db.runSql('INSERT INTO people (name) VALUES (?)', const [Value.varchar('Ada')]);

      await expectLater(
        db.runSql('INSERT INTO people (name) VALUES (?)', const [Value.varchar('ADA')]),
        throwsA(isA<UniqueConstraintError>()),
      );
      await db.dispose();
    });

    test('an index over an expression and one over a keyword-named column both create', () async {
      final declared = TableBuilder('people')
          .indexes(
            (i) => [
              i.name('people_group_idx').columns(const [IndexColumn.named('group', order: SortOrder.desc)]),
              i.name('people_email_idx').columns(const [IndexColumn.expression('lower(email)')]).unique(),
            ],
          )
          .columns((c) => {'group': c.text(), 'email': c.text()});
      final db = openDeclared('schema_indexes.db', declared);
      await db.open();
      await db.runSql('INSERT INTO people (email) VALUES (?)', const [Value.varchar('Ada@Example.com')]);

      await expectLater(
        db.runSql('INSERT INTO people (email) VALUES (?)', const [Value.varchar('ada@example.com')]),
        throwsA(isA<UniqueConstraintError>()),
      );
      await db.dispose();
    });

    test('an initially deferred foreign key lets a child land before its parent inside one transaction', () async {
      final declared = TableBuilder('children').columns(
        (c) => {
          'id': c.integer().isPrimary(),
          'parent_id': c.integer().references(
            const ColumnReference(table: 'parents', column: 'id', deferral: Deferral.initiallyDeferred),
          ),
        },
      );
      final db = LocalDatabase.forTesting(
        name: 'schema_deferred.db',
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE parents (id INTEGER PRIMARY KEY)');
          for (final statement in declared.statements) {
            await db.execute(statement);
          }
        },
      );
      await db.open();

      await db.runTransaction((txn) async {
        await txn.execute('INSERT INTO children (id, parent_id) VALUES (1, 7)');
        await txn.execute('INSERT INTO parents (id) VALUES (7)');
      });

      expect(await db.runRawQuery('SELECT id FROM children'), hasLength(1));
      await db.dispose();
    });

    test('a foreign key with no deferral refuses a child that lands before its parent', () async {
      final declared = TableBuilder('children').columns(
        (c) => {
          'id': c.integer().isPrimary(),
          'parent_id': c.integer().references(const ColumnReference(table: 'parents', column: 'id')),
        },
      );
      final db = LocalDatabase.forTesting(
        name: 'schema_immediate.db',
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE parents (id INTEGER PRIMARY KEY)');
          for (final statement in declared.statements) {
            await db.execute(statement);
          }
        },
      );
      await db.open();

      await expectLater(
        db.runTransaction((txn) => txn.execute('INSERT INTO children (id, parent_id) VALUES (1, 7)')),
        throwsA(isA<StoreError>()),
      );
      await db.dispose();
    });

    test('a CHECK constraint the DSL renders is actually enforced', () async {
      final declared = TableBuilder(
        'todos',
      ).checks((ck) => [ck.expression('length(title) > 0')]).columns((c) => {'title': c.text().isNullable(false)});

      final db = LocalDatabase.forTesting(
        name: 'schema_check.db',
        onCreate: (db, version) async {
          for (final statement in declared.statements) {
            await db.execute(statement);
          }
        },
      );
      await db.open();

      await expectLater(
        db.runSql('INSERT INTO todos (title) VALUES (?)', const [Value.varchar('')]),
        throwsA(isA<StoreError>()),
      );

      await db.dispose();
    });

    test('a STRICT table refuses a value that does not match its column type', () async {
      final declared = TableBuilder('kv').strict().columns((c) => {'key': c.text().isPrimary(), 'value': c.integer()});

      final db = LocalDatabase.forTesting(
        name: 'schema_strict.db',
        onCreate: (db, version) async {
          for (final statement in declared.statements) {
            await db.execute(statement);
          }
        },
      );
      await db.open();

      await expectLater(
        db.runSql('INSERT INTO kv (key, value) VALUES (?, ?)', const [
          Value.varchar('a'),
          Value.varchar('not a number'),
        ]),
        throwsA(isA<StoreError>()),
      );

      await db.dispose();
    });
  });
}
