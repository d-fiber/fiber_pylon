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

import 'dart:typed_data';

import 'package:fiber_pylon/fiber_pylon.dart';
import 'package:fiber_pylon/src/sdk/clients/local/database/engine/database.dart';
import 'package:fiber_pylon/src/sdk/clients/local/database/engine/schema/schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

typedef ColumnRecipe = ({
  String label,
  ColumnType type,
  String? defaultSql,
  DatabaseType? defaultValue,
  ColumnBuilder<dynamic, DatabaseType> Function(ColumnFactory c, {required bool notNull, required bool unique}) build,
});

ColumnRecipe recipe(
  String label,
  ColumnType type,
  String? defaultSql,
  DatabaseType? defaultValue,
  ColumnBuilder<dynamic, DatabaseType> Function(ColumnFactory c) make,
) => (
  label: label,
  type: type,
  defaultSql: defaultSql,
  defaultValue: defaultValue,
  build: (c, {required notNull, required unique}) {
    final builder = make(c)..isNullable(!notNull);
    if (unique) builder.unique();
    return builder;
  },
);

ColumnRecipe integerDefault(int value, String sql) => recipe(
  'integer default $value',
  ColumnType.integer,
  sql,
  Integer(value),
  (c) => c.integer().default_(Integer(value)),
);

ColumnRecipe realDefault(double value, String sql) =>
    recipe('real default $sql', ColumnType.real, sql, Real(value), (c) => c.real().default_(Real(value)));

ColumnRecipe textDefault(String value, String sql) => recipe(
  'text default ${value.replaceAll('\u0000', '<NUL>').replaceAll('\n', '<LF>')}',
  ColumnType.text,
  sql,
  Varchar(value),
  (c) => c.text().default_(Varchar(value)),
);

ColumnRecipe blobDefault(List<int> value, String sql) => recipe(
  'blob default $sql',
  ColumnType.blob,
  sql,
  Blob(Uint8List.fromList(value)),
  (c) => c.blob().default_(Blob(Uint8List.fromList(value))),
);

final integerRecipes = [
  integerDefault(0, '0'),
  integerDefault(-1, '-1'),
  integerDefault(9223372036854775807, '9223372036854775807'),
  integerDefault(-9223372036854775808, '-9223372036854775808'),
];

final realRecipes = [
  realDefault(0.25, '0.25'),
  realDefault(-0.5, '-0.5'),
  realDefault(5.0, '5.0'),
  realDefault(1e21, '1e+21'),
  realDefault(1e-7, '1e-7'),
];

final textRecipes = [
  textDefault('', "''"),
  textDefault("it's", "'it''s'"),
  textDefault('say "hi"', "'say \"hi\"'"),
  textDefault('two\nlines', "'two\nlines'"),
  textDefault('ünï 日本', "'ünï 日本'"),
  textDefault('a\u0000b', "'a' || char(0) || 'b'"),
  textDefault("'", "''''"),
  textDefault('semi; colon -- dash /* star */', "'semi; colon -- dash /* star */'"),
];

final blobRecipes = [
  blobDefault(const [], "X''"),
  blobDefault(const [0], "X'00'"),
  blobDefault(const [0, 255, 16], "X'00ff10'"),
];

final plainRecipes = [
  recipe('integer with no default', ColumnType.integer, null, null, (c) => c.integer()),
  recipe('real with no default', ColumnType.real, null, null, (c) => c.real()),
  recipe('text with no default', ColumnType.text, null, null, (c) => c.text()),
  recipe('blob with no default', ColumnType.blob, null, null, (c) => c.blob()),
  recipe(
    'integer with an expression default',
    ColumnType.integer,
    '1 + 2',
    const Integer(3),
    (c) => c.integer().defaultExpression('1 + 2'),
  ),
  recipe(
    'text with an expression default holding a quote',
    ColumnType.text,
    "lower('X''Y')",
    const Varchar("x'y"),
    (c) => c.text().defaultExpression("lower('X''Y')"),
  ),
];

final columnRecipes = <ColumnRecipe>[
  ...integerRecipes,
  ...realRecipes,
  ...textRecipes,
  ...blobRecipes,
  ...plainRecipes,
];

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    databaseFactoryFfi.setDatabasesPath('');
  });

  Future<LocalDatabase> openMemory(List<String> statements) async {
    final db = LocalDatabase(
      name: inMemoryDatabasePath,
      singleInstance: false,
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

  Future<int> autoIndexCount(LocalDatabase db, String table) async {
    final indexes = await db.rawQuery('PRAGMA index_list("$table")');
    return indexes.where((index) => index['origin'] == const DatabaseType.varchar('u')).length;
  }

  group('a single column, swept over type, default, nullability, uniqueness and STRICT', () {
    for (final recipe in columnRecipes) {
      for (final strict in [false, true]) {
        for (final notNull in [false, true]) {
          for (final unique in [false, true]) {
            final name =
                '${recipe.label}, ${strict ? 'STRICT' : 'not STRICT'}, ${notNull ? 'NOT NULL' : 'nullable'}, '
                '${unique ? 'UNIQUE' : 'not unique'}';
            test('reads back as declared: $name', () async {
              final TableBuilderBase<dynamic, ColumnFactory> base = strict
                  ? TableBuilder('t').strict()
                  : TableBuilder('t');
              final table = base.columns(
                (c) => {'id': c.integer().isPrimary(), 'v': recipe.build(c, notNull: notNull, unique: unique)},
              );
              final db = await openMemory(table.statements);

              final column = (await db.columns('t')).singleWhere((column) => column.name == 'v');
              expect(column.type, recipe.type, reason: 'declared type');
              expect(column.isNotNull, notNull, reason: 'NOT NULL');
              expect(column.defaultSql, recipe.defaultSql, reason: 'default text');
              expect(await autoIndexCount(db, 't'), unique ? 1 : 0, reason: 'unique constraint');
              final defaultValue = recipe.defaultValue;
              if (defaultValue != null) {
                await db.execute('INSERT INTO t DEFAULT VALUES');
                expect((await db.rawQuery('SELECT v FROM t')).single['v'], defaultValue, reason: 'stored default');
              }
              await db.dispose();
            });
          }
        }
      }
    }
  });

  group('a text column, swept over collation and STRICT', () {
    final cases = <(Collation?, String, String, int)>[
      (null, 'a', 'A', 0),
      (Collation.binary, 'a', 'A', 0),
      (Collation.noCase, 'a', 'A', 1),
      (Collation.noCase, 'é', 'É', 0),
      (Collation.rtrim, 'a', 'a  ', 1),
      (Collation.rtrim, 'a', 'A', 0),
    ];
    for (final (collation, stored, probe, matches) in cases) {
      for (final strict in [false, true]) {
        test(
          '${collation?.name ?? 'no collation'} matches "$probe" against "$stored" $matches time(s), strict $strict',
          () async {
            final TableBuilderBase<dynamic, ColumnFactory> base = strict
                ? TableBuilder('t').strict()
                : TableBuilder('t');
            final table = base.columns((c) {
              final text = c.text();
              return {'id': c.integer().isPrimary(), 'v': collation == null ? text : text.collation(collation)};
            });
            final db = await openMemory(table.statements);
            await db.execute('INSERT INTO t (v) VALUES (?)', [DatabaseType.varchar(stored)]);

            final rows = await db.rawQuery('SELECT count(*) AS n FROM t WHERE v = ?', [DatabaseType.varchar(probe)]);

            expect(rows.single['n']!.asInt, matches);
            await db.dispose();
          },
        );
      }
    }
  });

  group('primary keys, swept over type, arity, STRICT and WITHOUT ROWID', () {
    final singles = <(String, ColumnBuilder<dynamic, DatabaseType> Function(ColumnFactory), bool)>[
      ('integer', (c) => c.integer().isPrimary(), false),
      ('integer autoincrement', (c) => c.integer().isPrimary().autoincrement(), false),
      ('text', (c) => c.text().isPrimary(), true),
      ('real', (c) => c.real().isPrimary(), true),
      ('blob', (c) => c.blob().isPrimary(), true),
    ];
    for (final (label, build, refusesNull) in singles) {
      for (final strict in [false, true]) {
        for (final withoutRowid in [false, true]) {
          final autoincrement = label.contains('autoincrement');
          if (autoincrement && withoutRowid) continue;
          test('single $label key, strict $strict, without rowid $withoutRowid', () async {
            TableBuilderBase<dynamic, ColumnFactory> builder = strict ? TableBuilder('t').strict() : TableBuilder('t');
            if (withoutRowid) builder = builder.withoutRowid();
            final table = builder.columns((c) => {'k': build(c), 'v': c.integer()});
            final db = await openMemory(table.statements);

            final columns = await db.columns('t');
            expect(columns.first.primaryKeyPosition, 1);
            expect(columns.last.primaryKeyPosition, 0);
            final flags = (await db.rawQuery('PRAGMA table_list("t")')).single;
            expect(flags['strict']!.asInt, strict ? 1 : 0, reason: 'STRICT flag');
            expect(flags['wr']!.asInt, withoutRowid ? 1 : 0, reason: 'WITHOUT ROWID flag');
            if (refusesNull || withoutRowid) {
              await expectLater(db.execute('INSERT INTO t (k) VALUES (NULL)'), throwsA(isA<DatabaseError>()));
            } else {
              await db.execute('INSERT INTO t (k) VALUES (NULL)');
              expect((await db.rawQuery('SELECT k FROM t')).single['k'], const DatabaseType.integer(1));
            }
            if (autoincrement) {
              await db.execute('INSERT INTO t (k) VALUES (NULL)');
              await db.execute('DELETE FROM t');
              await db.execute('INSERT INTO t (k) VALUES (NULL)');
              expect((await db.rawQuery('SELECT k FROM t')).single['k'], const DatabaseType.integer(3));
            }
            await db.dispose();
          });
        }
      }
    }

    for (final strict in [false, true]) {
      for (final withoutRowid in [false, true]) {
        test('composite key of three mixed columns, strict $strict, without rowid $withoutRowid', () async {
          final open = TableBuilder('t').primaryKey((pk) => pk.columns(['c', 'a', 'b']));
          TableBuilderBase<dynamic, ColumnFactory> builder = strict ? open.strict() : open;
          if (withoutRowid) builder = builder.withoutRowid();
          final table = builder.columns((c) => {'a': c.integer(), 'b': c.text(), 'c': c.blob(), 'v': c.integer()});
          final db = await openMemory(table.statements);

          final positions = {for (final column in await db.columns('t')) column.name: column.primaryKeyPosition};
          expect(positions, {'a': 2, 'b': 3, 'c': 1, 'v': 0});
          for (final nullColumn in ['a', 'b', 'c']) {
            final values = {'a': '1', 'b': "'x'", 'c': "X'00'"}..[nullColumn] = 'NULL';
            await expectLater(
              db.execute('INSERT INTO t (a, b, c) VALUES (${values['a']}, ${values['b']}, ${values['c']})'),
              throwsA(isA<DatabaseError>()),
              reason: 'a null $nullColumn was stored',
            );
          }
          await db.dispose();
        });
      }
    }
  });

  group('foreign keys, swept over action, deferral, spelling and column count', () {
    final actions = <ReferentialAction?, String>{
      null: 'NO ACTION',
      ReferentialAction.noAction: 'NO ACTION',
      ReferentialAction.restrict: 'RESTRICT',
      ReferentialAction.cascade: 'CASCADE',
      ReferentialAction.setNull: 'SET NULL',
      ReferentialAction.setDefault: 'SET DEFAULT',
    };
    final deferrals = <Deferral?>[null, Deferral.initiallyImmediate, Deferral.initiallyDeferred];

    for (final onDelete in actions.entries) {
      for (final onUpdate in actions.entries) {
        for (final deferral in deferrals) {
          for (final spelling in ['column', 'table']) {
            test(
              '$spelling level, delete ${onDelete.value}, update ${onUpdate.value}, ${deferral?.name ?? 'not deferrable'}',
              () async {
                final parent = TableBuilder('parent').columns((c) => {'id': c.integer().isPrimary()});
                final DeclaredTable child;
                if (spelling == 'column') {
                  child = TableBuilder('child').columns(
                    (c) => {
                      'p': c
                          .integer()
                          .default_(const Integer(1))
                          .references(
                            ColumnReference(
                              table: 'parent',
                              column: 'id',
                              onDelete: onDelete.key,
                              onUpdate: onUpdate.key,
                              deferral: deferral,
                            ),
                          ),
                    },
                  );
                } else {
                  child = TableBuilder('child')
                      .foreignKeys((fk) {
                        var key = fk.columns(['p']).references('parent', ['id']);
                        if (onDelete.key != null) key = key.onDelete(onDelete.key!);
                        if (onUpdate.key != null) key = key.onUpdate(onUpdate.key!);
                        if (deferral != null) key = key.deferrable(deferral);
                        return [key];
                      })
                      .columns((c) => {'p': c.integer().default_(const Integer(1))});
                }
                final db = await openMemory([...parent.statements, ...child.statements]);

                final list = (await db.rawQuery('PRAGMA foreign_key_list("child")')).single;
                expect(list['table'], const DatabaseType.varchar('parent'));
                expect(list['from'], const DatabaseType.varchar('p'));
                expect(list['to'], const DatabaseType.varchar('id'));
                expect(list['on_delete'], DatabaseType.varchar(onDelete.value));
                expect(list['on_update'], DatabaseType.varchar(onUpdate.value));
                final sql = (await db.rawQuery(
                  "SELECT sql FROM sqlite_master WHERE name = 'child'",
                )).single['sql']!.asString;
                expect(
                  sql.contains('DEFERRABLE INITIALLY DEFERRED'),
                  deferral == Deferral.initiallyDeferred,
                  reason: 'deferred spelling in $sql',
                );
                expect(sql.contains('DEFERRABLE'), deferral != null, reason: 'deferrable spelling in $sql');
                if (deferral == Deferral.initiallyDeferred) {
                  await db.transaction((txn) async {
                    await txn.execute('INSERT INTO child (p) VALUES (7)');
                    await txn.execute('INSERT INTO parent (id) VALUES (7)');
                  });
                } else {
                  await expectLater(
                    db.transaction((txn) => txn.execute('INSERT INTO child (p) VALUES (7)')),
                    throwsA(isA<DatabaseError>()),
                  );
                }
                await db.dispose();
              },
            );
          }
        }
      }
    }

    test('a two-column key with implicit and explicit targets lists both columns in order', () async {
      final parent = TableBuilder(
        'parent',
      ).primaryKey((pk) => pk.columns(['a', 'b'])).columns((c) => {'a': c.integer(), 'b': c.integer()});
      final implicit = TableBuilder('implicit')
          .foreignKeys(
            (fk) => [
              fk.columns(['x', 'y']).references('parent'),
            ],
          )
          .columns((c) => {'x': c.integer(), 'y': c.integer()});
      final explicit = TableBuilder('explicit')
          .foreignKeys(
            (fk) => [
              fk.columns(['x', 'y']).references('parent', ['a', 'b']),
            ],
          )
          .columns((c) => {'x': c.integer(), 'y': c.integer()});
      final db = await openMemory([...parent.statements, ...implicit.statements, ...explicit.statements]);
      await db.execute('INSERT INTO parent (a, b) VALUES (1, 2)');

      await db.execute('INSERT INTO implicit (x, y) VALUES (1, 2)');
      await db.execute('INSERT INTO explicit (x, y) VALUES (1, 2)');

      await expectLater(db.execute('INSERT INTO implicit (x, y) VALUES (2, 1)'), throwsA(isA<DatabaseError>()));
      await expectLater(db.execute('INSERT INTO explicit (x, y) VALUES (2, 1)'), throwsA(isA<DatabaseError>()));
      await db.dispose();
    });
  });

  group('indexes, swept over order, collation, uniqueness, predicate and expression', () {
    for (final order in [null, SortOrder.asc, SortOrder.desc]) {
      for (final collation in [null, Collation.binary, Collation.noCase, Collation.rtrim]) {
        for (final unique in [false, true]) {
          for (final where in [null, 'b > 0']) {
            test(
              'order ${order?.name}, collation ${collation?.name}, ${unique ? 'unique' : 'plain'}, where $where',
              () async {
                final table = TableBuilder('t')
                    .indexes((i) {
                      final index = i.name('t_idx').columns([
                        IndexColumn.named('a', collation: collation, order: order),
                        const IndexColumn.named('b'),
                      ]);
                      final refined = unique ? index.unique() : index;
                      return [where == null ? refined : refined.where(where)];
                    })
                    .columns((c) => {'a': c.text(), 'b': c.integer()});
                final db = await openMemory(table.statements);

                final listed = (await db.rawQuery('PRAGMA index_list("t")')).single;
                expect(listed['unique']!.asInt, unique ? 1 : 0);
                expect(listed['partial']!.asInt, where == null ? 0 : 1);
                final parts = await db.rawQuery('PRAGMA index_xinfo("t_idx")');
                expect(parts.first['desc']!.asInt, order == SortOrder.desc ? 1 : 0);
                expect(parts.first['coll'], DatabaseType.varchar((collation ?? Collation.binary).name.toUpperCase()));
                await db.dispose();
              },
            );
          }
        }
      }
    }

    test('an index over an expression keeps its collation and covers the expression', () async {
      final table = TableBuilder('t')
          .indexes(
            (i) => [
              i.name('t_lower').columns(const [
                IndexColumn.expression('lower(a)', collation: Collation.noCase, order: SortOrder.desc),
              ]),
            ],
          )
          .columns((c) => {'a': c.text()});
      final db = await openMemory(table.statements);

      final part = (await db.rawQuery('PRAGMA index_xinfo("t_lower")')).first;

      expect(part['cid']!.asInt, -2);
      expect(part['coll'], const DatabaseType.varchar('NOCASE'));
      expect(part['desc']!.asInt, 1);
      await db.dispose();
    });
  });

  group('names that need quoting, swept over every place a name is written', () {
    const names = ['select', 'group', 'a b', 'q"r', "it's", 'ünï', 'x;y', '--', '/*', '1st', 'with\ttab'];
    for (final name in names) {
      test('table, column, constraint and index named ${name.replaceAll('\t', '<TAB>')}', () async {
        final parent = TableBuilder(
          name,
        ).columns((c) => {name: c.integer().isPrimary(), 'other': c.integer().unique()});
        final child = TableBuilder('${name}_child')
            .primaryKey((pk) => pk.columns([name, 'k']).name('pk $name'))
            .uniques(
              (u) => [
                u.columns([name, 'k']).name('uq $name'),
              ],
            )
            .checks((ck) => [ck.expression('"${name.replaceAll('"', '""')}" >= 0').name('ck $name')])
            .foreignKeys(
              (fk) => [
                fk.columns([name]).references(name, [name]).onDelete(ReferentialAction.cascade).name('fk $name'),
              ],
            )
            .indexes(
              (i) => [
                i.name('ix $name').columns([IndexColumn.named(name), const IndexColumn.named('k')]),
              ],
            )
            .columns((c) => {name: c.integer(), 'k': c.integer()});
        final db = await openMemory([...parent.statements, ...child.statements]);
        await db.execute('INSERT INTO "${name.replaceAll('"', '""')}" VALUES (1, 1)');
        await db.execute('INSERT INTO "${name.replaceAll('"', '""')}_child" VALUES (1, 1)');

        expect(await db.tableNames(), unorderedEquals([name, '${name}_child']));
        expect((await db.columns('${name}_child')).map((column) => column.name), [name, 'k']);
        await expectLater(
          db.execute('INSERT INTO "${name.replaceAll('"', '""')}_child" VALUES (2, 1)'),
          throwsA(isA<DatabaseError>()),
        );
        expect(await db.differences(child), isEmpty);
        await db.dispose();
      });
    }
  });

  group('generated columns, swept over storage', () {
    for (final storage in GeneratedStorage.values) {
      test('${storage.name} column is computed, hidden from writes and read back with its storage', () async {
        final table = TableBuilder('t').columns(
          (c) => {'a': c.integer(), 'g': c.integer().generated(GeneratedColumn(expression: 'a + 1', storage: storage))},
        );
        final db = await openMemory(table.statements);
        await db.execute('INSERT INTO t (a) VALUES (41)');

        expect((await db.rawQuery('SELECT g FROM t')).single['g'], const DatabaseType.integer(42));
        expect((await db.columns('t')).last.generated, storage);
        await expectLater(db.execute('INSERT INTO t (a, g) VALUES (1, 1)'), throwsA(isA<DatabaseError>()));
        await db.dispose();
      });
    }
  });
}
