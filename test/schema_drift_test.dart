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

import 'package:fiber_pylon/src/sdk/clients/local/database/engine/database.dart';
import 'package:fiber_pylon/src/sdk/clients/local/database/engine/schema/schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

DeclaredTable orders() => TableBuilder('orders')
    .checks((ck) => [ck.expression('total >= 0')])
    .foreignKeys(
      (fk) => [
        fk.columns(['customer_id']).references('customers', ['id']).onDelete(ReferentialAction.cascade),
      ],
    )
    .uniques(
      (u) => [
        u.columns(['customer_id', 'reference']),
      ],
    )
    .indexes(
      (i) => [
        i
            .name('orders_open_idx')
            .columns(const [IndexColumn.named('reference', collation: Collation.noCase)])
            .where('total > 0'),
      ],
    )
    .strict()
    .columns(
      (c) => {
        'id': c.integer().isPrimary().autoincrement(),
        'customer_id': c.integer().isNullable(false),
        'reference': c.text().isNullable(false).collation(Collation.noCase),
        'total': c.integer().isNullable(false).default_(const Integer(0)),
        'doubled': c.integer().generated(
          const GeneratedColumn(expression: 'total * 2', storage: GeneratedStorage.stored),
        ),
      },
    );

void main() {
  late Directory directory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pylon_schema_drift');
    databaseFactoryFfi.setDatabasesPath(directory.path);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  Future<LocalDatabase> openWith(String name, List<String> statements, {bool foreignKeys = true}) async {
    final db = LocalDatabase(
      name: name,
      onConfigure: foreignKeys ? null : (db) => db.execute('PRAGMA foreign_keys = OFF'),
      onCreate: (db, version) async {
        for (final statement in statements) {
          await db.execute(statement);
        }
      },
    );
    await db.open();
    return db;
  }

  Future<LocalDatabase> openCreatedFrom(String name, DeclaredTable declared, {bool foreignKeys = true}) =>
      openWith(name, declared.statements, foreignKeys: foreignKeys);

  Set<DifferenceKind> kinds(List<SchemaDifference> differences) => {for (final one in differences) one.kind};

  group('LocalDatabase.differences', () {
    test('reports nothing for a table created from its own declaration, whatever the declaration holds', () async {
      final db = await openCreatedFrom('drift_same.db', orders());

      expect(await db.differences(orders()), isEmpty);
      await db.dispose();
    });

    test('reports a declared table that the database does not have', () async {
      final db = await openWith('drift_missing.db', const []);

      final differences = await db.differences(orders());

      expect(
        kinds(differences),
        {
          DifferenceKind.missingTable,
          DifferenceKind.foreignKeysDisabled,
        }.difference({DifferenceKind.foreignKeysDisabled}),
      );
      expect(differences.single.message, 'Table "orders" is declared and missing from the database.');
      await db.dispose();
    });

    test('reports a column that is missing, one that is unexpected and one that changed', () async {
      final declared = TableBuilder('t').columns(
        (c) => {
          'id': c.integer().isPrimary(),
          'kept': c.integer().isNullable(false),
          'total': c.integer().isNullable(false).default_(const Integer(0)),
        },
      );
      final db = await openWith('drift_columns.db', [
        'CREATE TABLE t ("id" INTEGER PRIMARY KEY, "kept" TEXT NOT NULL, "extra" INTEGER)',
      ], foreignKeys: false);

      final differences = await db.differences(declared);

      expect(differences.map((one) => one.message), [
        'Table "t", "kept" is declared as INTEGER NOT NULL and is TEXT NOT NULL in the database.',
        'Table "t", "total" is declared as INTEGER NOT NULL DEFAULT 0 and missing from the database.',
        'Table "t", "extra" is INTEGER in the database and not declared.',
      ]);
      await db.dispose();
    });

    test('reports a default, a nullability and a primary key position that changed', () async {
      final declared = TableBuilder('t')
          .primaryKey((pk) => pk.columns(['a', 'b']))
          .columns(
            (c) => {'a': c.integer(), 'b': c.integer(), 'c': c.text().isNullable(false).default_(const Varchar('x'))},
          );
      final db = await openWith('drift_column_details.db', [
        'CREATE TABLE t (a INTEGER NOT NULL, b INTEGER NOT NULL, c TEXT DEFAULT (\'y\'), PRIMARY KEY (b, a))',
      ], foreignKeys: false);

      final differences = await db.differences(declared);

      expect(differences.map((one) => (one.kind, one.subject)), [
        (DifferenceKind.columnDiffers, 'a'),
        (DifferenceKind.columnDiffers, 'b'),
        (DifferenceKind.columnDiffers, 'c'),
        (DifferenceKind.keyDiffers, null),
      ]);
      await db.dispose();
    });

    test('reports a unique constraint that the database does not carry', () async {
      final declared = TableBuilder('t')
          .uniques(
            (u) => [
              u.columns(['a', 'b']),
            ],
          )
          .columns((c) => {'a': c.integer(), 'b': c.integer()});
      final db = await openWith('drift_unique.db', [
        'CREATE TABLE t ("a" INTEGER, "b" INTEGER, UNIQUE ("a"))',
      ], foreignKeys: false);

      final differences = await db.differences(declared);

      expect(differences.single.kind, DifferenceKind.keyDiffers);
      expect(differences.single.expected, 'UNIQUE (a COLLATE BINARY, b COLLATE BINARY)');
      expect(differences.single.actual, 'UNIQUE (a COLLATE BINARY)');
      await db.dispose();
    });

    test('reports a foreign key whose action changed', () async {
      final db = await openWith('drift_foreign_key.db', [
        'CREATE TABLE customers (id INTEGER PRIMARY KEY)',
        'CREATE TABLE orders ("id" INTEGER PRIMARY KEY AUTOINCREMENT, "customer_id" INTEGER NOT NULL, '
            '"reference" TEXT NOT NULL COLLATE NOCASE, "total" INTEGER NOT NULL DEFAULT (0), '
            '"doubled" INTEGER GENERATED ALWAYS AS (total * 2) STORED, '
            'UNIQUE ("customer_id", "reference"), CHECK (total >= 0), '
            'FOREIGN KEY ("customer_id") REFERENCES "customers" ("id")) STRICT',
        'CREATE INDEX "orders_open_idx" ON "orders" ("reference" COLLATE NOCASE) WHERE total > 0',
      ]);

      final differences = await db.differences(orders());

      expect(differences.single.kind, DifferenceKind.foreignKeyDiffers);
      expect(differences.single.expected, contains('ON DELETE CASCADE'));
      expect(differences.single.actual, contains('ON DELETE NO ACTION'));
      await db.dispose();
    });

    test('reports an index that is missing, one that changed and one nobody declared', () async {
      final declared = TableBuilder('t')
          .indexes(
            (i) => [
              i.name('t_a').columns(const [IndexColumn.named('a')]),
              i.name('t_b').columns(const [IndexColumn.named('b')]).where('b > 0'),
            ],
          )
          .columns((c) => {'a': c.integer(), 'b': c.integer()});
      final db = await openWith('drift_indexes.db', [
        'CREATE TABLE "t" ("a" INTEGER, "b" INTEGER)',
        'CREATE INDEX "t_b" ON "t" ("b")',
        'CREATE INDEX "t_stray" ON "t" ("a", "b")',
      ], foreignKeys: false);

      final differences = await db.differences(declared);

      expect(differences.map((one) => (one.kind, one.subject)), [
        (DifferenceKind.missingIndex, 't_a'),
        (DifferenceKind.indexDiffers, 't_b'),
        (DifferenceKind.unexpectedIndex, 't_stray'),
      ]);
      await db.dispose();
    });

    test('reports STRICT and WITHOUT ROWID when the database was created without them', () async {
      final declared = TableBuilder('t').strict().withoutRowid().columns((c) => {'a': c.integer().isPrimary()});
      final db = await openWith('drift_options.db', ['CREATE TABLE "t" ("a" INTEGER PRIMARY KEY)'], foreignKeys: false);

      final differences = await db.differences(declared);

      expect(differences.map((one) => one.kind), contains(DifferenceKind.optionDiffers));
      expect(
        differences.firstWhere((one) => one.kind == DifferenceKind.optionDiffers).message,
        'Table "t" is declared STRICT, WITHOUT ROWID and is without options in the database.',
      );
      await db.dispose();
    });

    test('reports a changed CHECK, a changed collation and a changed deferral, which no pragma shows', () async {
      final declared = TableBuilder('t')
          .checks((ck) => [ck.expression('a > 0')])
          .foreignKeys(
            (fk) => [
              fk.columns(['p']).references('t', ['a']).deferrable(Deferral.initiallyDeferred),
            ],
          )
          .columns((c) => {'a': c.integer().isPrimary(), 'p': c.integer(), 's': c.text().collation(Collation.noCase)});
      final same = await openCreatedFrom('drift_text_same.db', declared);
      expect(await same.differences(declared), isEmpty);
      await same.dispose();

      final changedCheck = TableBuilder('t')
          .checks((ck) => [ck.expression('a >= 0')])
          .foreignKeys(
            (fk) => [
              fk.columns(['p']).references('t', ['a']).deferrable(Deferral.initiallyDeferred),
            ],
          )
          .columns((c) => {'a': c.integer().isPrimary(), 'p': c.integer(), 's': c.text().collation(Collation.noCase)});
      final changedCollation = TableBuilder('t')
          .checks((ck) => [ck.expression('a > 0')])
          .foreignKeys(
            (fk) => [
              fk.columns(['p']).references('t', ['a']).deferrable(Deferral.initiallyDeferred),
            ],
          )
          .columns((c) => {'a': c.integer().isPrimary(), 'p': c.integer(), 's': c.text()});
      final changedDeferral = TableBuilder('t')
          .checks((ck) => [ck.expression('a > 0')])
          .foreignKeys(
            (fk) => [
              fk.columns(['p']).references('t', ['a']),
            ],
          )
          .columns((c) => {'a': c.integer().isPrimary(), 'p': c.integer(), 's': c.text().collation(Collation.noCase)});
      final db = await openCreatedFrom('drift_text.db', declared);

      for (final changed in [changedCheck, changedCollation, changedDeferral]) {
        expect((await db.differences(changed)).map((one) => one.kind), [DifferenceKind.definitionDiffers]);
      }
      await db.dispose();
    });

    test('accepts a column added with ALTER TABLE when the declaration lists it last', () async {
      final declared = TableBuilder(
        't',
      ).checks((ck) => [ck.expression('a > 0')]).columns((c) => {'a': c.integer(), 'b': c.text()});
      final db = await openWith('drift_alter.db', [
        'CREATE TABLE "t" ("a" INTEGER, CHECK (a > 0))',
        'ALTER TABLE "t" ADD COLUMN "b" TEXT',
      ], foreignKeys: false);

      expect(await db.differences(declared), isEmpty);
      await db.dispose();
    });

    test('warns that foreign keys are declared while the connection does not enforce them', () async {
      final child = TableBuilder('child').columns(
        (c) => {'id': c.integer().isPrimary(), 'p': c.integer().references(const ColumnReference(table: 'parent'))},
      );
      final off = await openCreatedFrom('drift_pragma_off.db', child, foreignKeys: false);
      final on = await openCreatedFrom('drift_pragma_on.db', child);

      expect((await off.differences(child)).map((one) => one.kind), [DifferenceKind.foreignKeysDisabled]);
      expect(await on.differences(child), isEmpty);
      await off.dispose();
      await on.dispose();
    });

    test(
      'reads differences and columns from inside a transaction on the same database without waiting forever',
      () async {
        final declared = orders();
        final db = await openCreatedFrom('drift_in_transaction.db', declared);

        final result = await db
            .runTransaction((txn) async => (await db.differences(declared), await db.listColumns('orders')))
            .timeout(const Duration(seconds: 5));

        expect(result.$1, isEmpty);
        expect(result.$2, isNotEmpty);
        await db.dispose();
      },
    );

    test('reads a column back as a typed ColumnType with its default, generation and primary key position', () async {
      final declared = orders();
      final db = await openCreatedFrom('drift_columns_typed.db', declared);

      final columns = {for (final column in await db.listColumns('orders')) column.name: column};

      expect(columns['id']!.type, ColumnType.integer);
      expect(columns['id']!.primaryKeyPosition, 1);
      expect(columns['total']!.defaultSql, '0');
      expect(columns['reference']!.type, ColumnType.text);
      expect(columns['doubled']!.generated, GeneratedStorage.stored);
      expect(columns['customer_id']!.isPrimaryKey, isFalse);
      await db.dispose();
    });

    test('reads no ColumnType for a declared type outside the five a STRICT table takes', () async {
      final db = await openWith('drift_type.db', ['CREATE TABLE t (a VARCHAR(20), b, c integer)'], foreignKeys: false);

      final columns = await db.listColumns('t');

      expect(columns.map((column) => column.type), [null, null, ColumnType.integer]);
      await db.dispose();
    });
  });
}
