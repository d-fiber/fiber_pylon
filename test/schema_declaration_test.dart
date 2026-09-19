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

import 'dart:io';

import 'package:fiber_pylon/fiber_pylon.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

Matcher refusedWith(List<String> fragments) => throwsA(
  isA<ArgumentError>().having(
    (error) => error.message.toString(),
    'message',
    allOf([for (final fragment in fragments) contains(fragment)]),
  ),
);

const storedCopyOfA = GeneratedColumn(expression: 'a', storage: GeneratedStorage.stored);

void main() {
  group('TableBuilder (declarations SQLite accepts and then does not honour)', () {
    test('makes an autoincrement column the primary key instead of dropping the autoincrement', () {
      final declared = TableBuilder('t').columns((c) => {'id': c.integer().autoincrement()});

      expect(declared.columns['id']!.isPrimary, isTrue);
      expect(declared.columns['id']!.autoincrement, isTrue);
      expect(declared.statements.first, contains('PRIMARY KEY AUTOINCREMENT'));
    });

    test('offers an ANY column only on a STRICT table, where SQLite does not turn 007 into 7', () {
      expect(TableBuilder('t').strict().columns((c) => {'a': c.any()}).strict, isTrue);
    });

    test('refuses a NULL default on a NOT NULL column, which fails every insert that omits it', () {
      expect(
        () => TableBuilder(
          't',
        ).strict().columns((c) => {'a': c.any().isNullable(false).default_(const DatabaseType.nil())}),
        refusedWith(['column "a": a NULL default on a NOT NULL column']),
      );
    });

    test('refuses SET NULL on a NOT NULL column, at the column level and the table level', () {
      expect(
        () => TableBuilder('t').columns(
          (c) => {
            'a': c
                .integer()
                .isNullable(false)
                .references(const ColumnReference(table: 'p', onDelete: ReferentialAction.setNull)),
          },
        ),
        refusedWith(['column "a": SET NULL on a NOT NULL column']),
      );
      expect(
        () => TableBuilder('t')
            .foreignKeys(
              (fk) => [
                fk.columns(['a']).references('p').onUpdate(ReferentialAction.setNull),
              ],
            )
            .columns((c) => {'a': c.integer().isNullable(false)}),
        refusedWith(['foreign key (a): SET NULL on a NOT NULL column']),
      );
    });

    test('refuses SET DEFAULT on a column that has no default, which would set it to NULL', () {
      expect(
        () => TableBuilder('t')
            .foreignKeys(
              (fk) => [
                fk.columns(['a']).references('p').onDelete(ReferentialAction.setDefault),
              ],
            )
            .columns((c) => {'a': c.integer()}),
        refusedWith(['foreign key (a): SET DEFAULT on a column with no default']),
      );
      expect(
        TableBuilder('t')
            .foreignKeys(
              (fk) => [
                fk.columns(['a']).references('p').onDelete(ReferentialAction.setDefault),
              ],
            )
            .columns((c) => {'a': c.integer().default_(const Integer(0))})
            .foreignKeys,
        hasLength(1),
      );
    });

    test('refuses a foreign key that would have to rewrite a generated column', () {
      expect(
        () => TableBuilder('t').columns(
          (c) => {
            'a': c.integer(),
            'b': c
                .integer()
                .generated(storedCopyOfA)
                .references(const ColumnReference(table: 'p', onDelete: ReferentialAction.setNull)),
          },
        ),
        refusedWith(['column "b": a generated column cannot be rewritten']),
      );
      expect(
        () => TableBuilder('t').columns(
          (c) => {
            'a': c.integer(),
            'b': c
                .integer()
                .generated(storedCopyOfA)
                .references(const ColumnReference(table: 'p', onUpdate: ReferentialAction.cascade)),
          },
        ),
        refusedWith(['column "b": a generated column cannot be rewritten']),
      );
      expect(
        TableBuilder('t')
            .columns(
              (c) => {
                'a': c.integer(),
                'b': c
                    .integer()
                    .generated(storedCopyOfA)
                    .references(const ColumnReference(table: 'p', onDelete: ReferentialAction.cascade)),
              },
            )
            .columns,
        hasLength(2),
      );
    });

    test('lists every problem in one error so a developer fixes them together', () {
      expect(
        () => TableBuilder('t').strict().columns(
          (c) => {
            'x': c.any().isNullable(false).default_(const DatabaseType.nil()),
            'y': c
                .integer()
                .isNullable(false)
                .references(const ColumnReference(table: 'p', onDelete: ReferentialAction.setNull)),
          },
        ),
        refusedWith(['a NULL default on a NOT NULL column', 'SET NULL on a NOT NULL column']),
      );
    });

    test('leaves to SQLite what it already refuses clearly when the table is created', () {
      expect(TableBuilder('t').columns((c) => {'a': c.integer()}).columns, hasLength(1));
      expect(
        TableBuilder('t')
            .indexes(
              (i) => [
                i.name('t_idx').columns(const [IndexColumn.named('nope')]),
              ],
            )
            .columns((c) => {'a': c.integer()})
            .indexes,
        hasLength(1),
      );
    });
  });

  group('DeclaredTable (rendering that a key must refuse null)', () {
    test('makes every column of a composite primary key NOT NULL, even one declared nullable', () {
      final table = TableBuilder(
        'm',
      ).primaryKey((pk) => pk.columns(['a', 'b'])).columns((c) => {'a': c.integer().isNullable(), 'b': c.text()});

      expect(table.columns.values.map((column) => column.notNull), [true, true]);
      expect(table.statements, ['CREATE TABLE "m" ("a" INTEGER NOT NULL, "b" TEXT NOT NULL, PRIMARY KEY ("a", "b"))']);
    });

    test('spells NOT NULL on every primary key that is not an integer and on none that is', () {
      final table = TableBuilder('keys').columns((c) => {'t': c.text().isPrimary()});
      final integer = TableBuilder('counters').columns((c) => {'id': c.integer().isPrimary().autoincrement()});

      expect(table.statements, ['CREATE TABLE "keys" ("t" TEXT PRIMARY KEY NOT NULL)']);
      expect(integer.statements, ['CREATE TABLE "counters" ("id" INTEGER PRIMARY KEY AUTOINCREMENT)']);
    });

    test('tells two tables apart when only the order of their columns differs', () {
      final ab = TableBuilder('t').columns((c) => {'a': c.integer(), 'b': c.integer()});
      final ba = TableBuilder('t').columns((c) => {'b': c.integer(), 'a': c.integer()});

      expect(ab, isNot(ba));
      expect(ab, TableBuilder('t').columns((c) => {'a': c.integer(), 'b': c.integer()}));
    });

    test('renders a text default holding a NUL as a concatenation, since a NUL ends an SQL statement', () {
      final table = TableBuilder('t').columns((c) => {'a': c.text().default_(const Varchar('a\u0000b\u0000'))});

      expect(table.statements, ["CREATE TABLE \"t\" (\"a\" TEXT DEFAULT ('a' || char(0) || 'b' || char(0) || ''))"]);
    });
  });

  group('DeclaredTable (against a real database)', () {
    late Directory directory;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('pylon_schema_declaration');
      databaseFactoryFfi.setDatabasesPath(directory.path);
    });

    tearDown(() async {
      await directory.delete(recursive: true);
    });

    LocalDatabase openDeclared(String name, List<DeclaredTable> tables, {bool foreignKeys = false}) => LocalDatabase(
      name: name,
      onConfigure: foreignKeys ? (db) => db.execute('PRAGMA foreign_keys = ON') : null,
      onCreate: (db, version) async {
        for (final table in tables) {
          for (final statement in table.statements) {
            await db.execute(statement);
          }
        }
      },
    );

    test('a text, real and blob primary key each refuse null', () async {
      final tables = [
        TableBuilder('texts').columns((c) => {'k': c.text().isPrimary()}),
        TableBuilder('reals').columns((c) => {'k': c.real().isPrimary()}),
        TableBuilder('blobs').columns((c) => {'k': c.blob().isPrimary()}),
      ];
      final db = openDeclared('declaration_keys.db', tables);
      await db.open();

      for (final table in ['texts', 'reals', 'blobs']) {
        await expectLater(
          db.execute('INSERT INTO $table (k) VALUES (NULL)'),
          throwsA(isA<DatabaseError>()),
          reason: '$table accepted a null primary key',
        );
      }
      await db.dispose();
    });

    test('an integer primary key still hands out the next id when given null', () async {
      final counters = TableBuilder('counters').columns((c) => {'id': c.integer().isPrimary(), 'n': c.integer()});
      final db = openDeclared('declaration_rowid.db', [counters]);
      await db.open();

      await db.execute('INSERT INTO counters (id, n) VALUES (NULL, 1)');

      expect((await db.rawQuery('SELECT id FROM counters')).single['id']!.asInt, 1);
      await db.dispose();
    });

    test('every column of a composite primary key refuses null', () async {
      final memberships = TableBuilder('memberships')
          .primaryKey((pk) => pk.columns(['account_id', 'group_id']))
          .columns((c) => {'account_id': c.integer(), 'group_id': c.integer()});
      final db = openDeclared('declaration_composite.db', [memberships]);
      await db.open();

      await expectLater(
        db.execute('INSERT INTO memberships (account_id, group_id) VALUES (NULL, 1)'),
        throwsA(isA<DatabaseError>()),
      );
      await db.dispose();
    });

    test('a text default holding a NUL is stored with the NUL', () async {
      final declared = TableBuilder(
        't',
      ).columns((c) => {'id': c.integer().isPrimary(), 'a': c.text().default_(const Varchar('a\u0000b'))});
      final db = openDeclared('declaration_nul.db', [declared]);
      await db.open();

      await db.execute('INSERT INTO t DEFAULT VALUES');

      expect((await db.rawQuery('SELECT a FROM t')).single['a']!.asString, 'a\u0000b');
      await db.dispose();
    });

    test('columns lists a generated column that PRAGMA table_info leaves out', () async {
      final declared = TableBuilder('t').columns(
        (c) => {
          'a': c.integer(),
          'b': c.integer().generated(const GeneratedColumn(expression: 'a + 1', storage: GeneratedStorage.virtual)),
          'c': c.integer().generated(storedCopyOfA),
        },
      );
      final db = openDeclared('declaration_generated.db', [declared]);
      await db.open();

      expect((await db.columns('t')).map((column) => column.name), ['a', 'b', 'c']);
      await db.dispose();
    });

    Future<LocalDatabase> openWithTables(String name, List<DeclaredTable> tables) async {
      final db = openDeclared(name, tables, foreignKeys: true);
      await db.open();
      return db;
    }

    test('a foreign key onto a column that is not unique is created and refuses the first child', () async {
      final parent = TableBuilder('parent').columns((c) => {'id': c.integer().isPrimary(), 'x': c.integer()});
      final child = TableBuilder('child').columns(
        (c) => {
          'id': c.integer().isPrimary(),
          'p': c.integer().references(const ColumnReference(table: 'parent', column: 'x')),
        },
      );
      final db = await openWithTables('declaration_not_unique.db', [parent, child]);
      await db.execute('INSERT INTO parent (id, x) VALUES (1, 1)');

      await expectLater(db.execute('INSERT INTO child (id, p) VALUES (1, 1)'), throwsA(isA<DatabaseError>()));
      await db.dispose();
    });

    test('a foreign key onto a table nobody declared is created and refuses the first child', () async {
      final child = TableBuilder('child').columns(
        (c) => {'id': c.integer().isPrimary(), 'p': c.integer().references(const ColumnReference(table: 'nope'))},
      );
      final db = await openWithTables('declaration_undeclared.db', [child]);

      await expectLater(db.execute('INSERT INTO child (id, p) VALUES (1, 1)'), throwsA(isA<DatabaseError>()));
      await db.dispose();
    });

    Future<LocalDatabase> openRaw(String name, List<String> statements) async {
      final db = LocalDatabase(
        name: name,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          for (final statement in statements) {
            await db.execute(statement);
          }
        },
      );
      await db.open();
      return db;
    }

    test('SET NULL on a NOT NULL column is created and fails when the parent row goes', () async {
      final db = await openRaw('declaration_set_null.db', [
        'CREATE TABLE parent (id INTEGER PRIMARY KEY)',
        'CREATE TABLE child (p INTEGER NOT NULL REFERENCES parent ON DELETE SET NULL)',
      ]);
      await db.execute('INSERT INTO parent (id) VALUES (1)');
      await db.execute('INSERT INTO child (p) VALUES (1)');

      await expectLater(db.execute('DELETE FROM parent'), throwsA(isA<DatabaseError>()));
      await db.dispose();
    });

    test('SET DEFAULT on a column with no default is created and sets the column to NULL', () async {
      final db = await openRaw('declaration_set_default.db', [
        'CREATE TABLE parent (id INTEGER PRIMARY KEY)',
        'CREATE TABLE child (p INTEGER REFERENCES parent ON DELETE SET DEFAULT)',
      ]);
      await db.execute('INSERT INTO parent (id) VALUES (1)');
      await db.execute('INSERT INTO child (p) VALUES (1)');

      await db.execute('DELETE FROM parent');

      expect((await db.rawQuery('SELECT p FROM child')).single['p'], const DatabaseType.nil());
      await db.dispose();
    });

    test('a foreign key that rewrites a generated column is created and fails when it fires', () async {
      final db = await openRaw('declaration_generated_action.db', [
        'CREATE TABLE parent (id INTEGER PRIMARY KEY)',
        'CREATE TABLE child (a INTEGER, b INTEGER GENERATED ALWAYS AS (a) STORED REFERENCES parent ON DELETE SET NULL)',
      ]);
      await db.execute('INSERT INTO parent (id) VALUES (1)');
      await db.execute('INSERT INTO child (a) VALUES (1)');

      await expectLater(db.execute('DELETE FROM parent'), throwsA(isA<DatabaseError>()));
      await db.dispose();
    });

    test('a NULL default on a NOT NULL column is created and fails every insert that omits it', () async {
      final db = await openRaw('declaration_null_default.db', [
        'CREATE TABLE t (a ANY NOT NULL DEFAULT (NULL)) STRICT',
      ]);

      await expectLater(db.execute('INSERT INTO t DEFAULT VALUES'), throwsA(isA<DatabaseError>()));
      await db.dispose();
    });

    test('an ANY column outside a STRICT table turns the text 007 into the integer 7', () async {
      final db = await openRaw('declaration_any.db', [
        'CREATE TABLE loose (a ANY)',
        'CREATE TABLE tight (a ANY) STRICT',
      ]);
      await db.execute("INSERT INTO loose VALUES ('007')");
      await db.execute("INSERT INTO tight VALUES ('007')");

      expect((await db.rawQuery('SELECT a FROM loose')).single['a'], const DatabaseType.integer(7));
      expect((await db.rawQuery('SELECT a FROM tight')).single['a'], const DatabaseType.varchar('007'));
      await db.dispose();
    });
    test('a declared foreign key is not enforced on a connection that switched PRAGMA foreign_keys off', () async {
      final parent = TableBuilder('parent').columns((c) => {'id': c.integer().isPrimary()});
      final child = TableBuilder(
        'child',
      ).columns((c) => {'p': c.integer().references(const ColumnReference(table: 'parent'))});
      final db = LocalDatabase(
        name: 'declaration_pragma_off.db',
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = OFF'),
        onCreate: (db, version) async {
          for (final statement in [...parent.statements, ...child.statements]) {
            await db.execute(statement);
          }
        },
      );
      await db.open();

      await db.execute('INSERT INTO child (p) VALUES (99)');

      expect(await db.rawQuery('SELECT p FROM child'), hasLength(1));
      await db.dispose();
    });
  });
}
