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

part of '../database.dart';

/// What kind of disagreement a [SchemaDifference] reports.
enum DifferenceKind {
  /// The declaration has foreign keys and this connection does not enforce
  /// them.
  foreignKeysDisabled,

  /// The declared table does not exist in the database.
  missingTable,

  /// A declared column is missing from the table on disk.
  missingColumn,

  /// The table on disk has a column the declaration does not.
  unexpectedColumn,

  /// A column exists on both sides with another type, nullability, primary
  /// key position, default or generation.
  columnDiffers,

  /// The `UNIQUE` and `PRIMARY KEY` constraints on disk are not the declared
  /// ones.
  keyDiffers,

  /// The foreign keys on disk are not the declared ones.
  foreignKeyDiffers,

  /// A declared index is missing from the database.
  missingIndex,

  /// The database has an index on the table that the declaration does not.
  unexpectedIndex,

  /// An index of the declared name exists with another definition.
  indexDiffers,

  /// `STRICT` or `WITHOUT ROWID` is not what the declaration says.
  optionDiffers,

  /// Everything above agrees, yet the stored `CREATE TABLE` text differs from
  /// the declared one. What a pragma cannot show lives here: `CHECK`
  /// constraints, column collations, deferral of a foreign key, generated
  /// expressions, `AUTOINCREMENT` and constraint names.
  definitionDiffers,
}

/// One way a table on disk no longer matches the [DeclaredTable] that is
/// meant to have created it.
final class SchemaDifference extends Equatable {
  /// Wraps every field [LocalDatabase.differences] compared.
  const SchemaDifference({
    required this.table,
    required this.kind,
    required this.expected,
    required this.actual,
    this.subject,
  });

  /// The declared table this difference belongs to.
  final String table;

  /// What kind of disagreement this is.
  final DifferenceKind kind;

  /// The column or index this difference is about. Null when it concerns the
  /// table as a whole.
  final String? subject;

  /// What the declaration says, or null when it says nothing about it.
  final String? expected;

  /// What the database holds, or null when it holds nothing there.
  final String? actual;

  /// A sentence a developer can read in a log.
  String get message {
    final where = subject == null ? 'Table "$table"' : 'Table "$table", "$subject"';
    return switch (kind) {
      DifferenceKind.foreignKeysDisabled =>
        '$where declares foreign keys, but this connection has foreign_keys off, so SQLite enforces none of them. '
            'Run PRAGMA foreign_keys = ON in onConfigure.',
      DifferenceKind.missingTable => '$where is declared and missing from the database.',
      DifferenceKind.missingColumn => '$where is declared as $expected and missing from the database.',
      DifferenceKind.unexpectedColumn => '$where is $actual in the database and not declared.',
      DifferenceKind.columnDiffers => '$where is declared as $expected and is $actual in the database.',
      DifferenceKind.keyDiffers => '$where declares keys [$expected] and the database has [$actual].',
      DifferenceKind.foreignKeyDiffers => '$where declares foreign keys [$expected] and the database has [$actual].',
      DifferenceKind.missingIndex => '$where is declared as $expected and missing from the database.',
      DifferenceKind.unexpectedIndex => '$where exists in the database as $actual and is not declared.',
      DifferenceKind.indexDiffers => '$where is declared as $expected and is $actual in the database.',
      DifferenceKind.optionDiffers => '$where is declared $expected and is $actual in the database.',
      DifferenceKind.definitionDiffers =>
        '$where is stored as $actual and declared as $expected. Something a pragma cannot show has changed.',
    };
  }

  @override
  String toString() => message;

  @override
  List<Object?> get props => [table, kind, subject, expected, actual];
}

typedef _TableFacts = ({
  List<ColumnInfo> columns,
  Set<String> keys,
  Set<String> foreignKeys,
  Map<String, String> indexes,
  String? options,
  String? sql,
});

extension _SchemaComparison on LocalDatabase {
  Future<List<Map<String, Object?>>> _pragma(DatabaseExecutor db, String pragma, String table) =>
      db.rawQuery('PRAGMA $pragma(${_quotedIdentifier(table)})');

  Future<List<ColumnInfo>> _columnsOf(DatabaseExecutor db, String table) async {
    final extended = await _pragma(db, 'table_xinfo', table);
    final rows = extended.isNotEmpty ? extended : await _pragma(db, 'table_info', table);
    return rows.map((row) => ColumnInfo._fromRow(_fromNativeRow(row))).toList();
  }

  Future<Set<String>> _keysOf(DatabaseExecutor db, String table) async {
    final keys = <String>{};
    for (final index in await _pragma(db, 'index_list', table)) {
      final origin = index['origin'];
      if (origin != 'pk' && origin != 'u') continue;
      final parts = [
        for (final part in await _pragma(db, 'index_xinfo', index['name']! as String))
          if (part['key'] == 1) '${part['name']}${part['desc'] == 1 ? ' DESC' : ''} COLLATE ${part['coll']}',
      ];
      keys.add('${origin == 'pk' ? 'PRIMARY KEY' : 'UNIQUE'} (${parts.join(', ')})');
    }
    return keys;
  }

  Future<Set<String>> _foreignKeysOf(DatabaseExecutor db, String table) async {
    final byId = <Object?, List<Map<String, Object?>>>{};
    for (final row in await _pragma(db, 'foreign_key_list', table)) {
      byId.putIfAbsent(row['id'], () => []).add(row);
    }
    return {
      for (final parts in byId.values)
        '(${parts.map((part) => part['from']).join(', ')}) REFERENCES ${parts.first['table']}'
            '(${parts.map((part) => part['to'] ?? 'primary key').join(', ')}) '
            'ON DELETE ${parts.first['on_delete']} ON UPDATE ${parts.first['on_update']}',
    };
  }

  Future<String?> _optionsOf(DatabaseExecutor db, String table) async {
    final rows = await _pragma(db, 'table_list', table);
    if (rows.isEmpty) return null;
    return [if (rows.first['strict'] == 1) 'STRICT', if (rows.first['wr'] == 1) 'WITHOUT ROWID'].join(', ');
  }

  Future<_TableFacts> _factsOf(DatabaseExecutor db, String table) async {
    final master = await db.rawQuery(
      "SELECT type, name, sql FROM sqlite_master WHERE tbl_name = ? AND sql IS NOT NULL AND type IN ('table', 'index')",
      [table],
    );
    return (
      columns: await _columnsOf(db, table),
      keys: await _keysOf(db, table),
      foreignKeys: await _foreignKeysOf(db, table),
      indexes: {
        for (final row in master)
          if (row['type'] == 'index') row['name']! as String: row['sql']! as String,
      },
      options: await _optionsOf(db, table),
      sql: master.where((row) => row['type'] == 'table').map((row) => row['sql']! as String).firstOrNull,
    );
  }

  Future<_TableFacts> _factsOfDeclared(DeclaredTable declared) async {
    final scratch = await _factory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      for (final statement in declared.statements) {
        await scratch.execute(statement);
      }
      return await _factsOf(scratch, declared.name);
    } finally {
      await scratch.close();
    }
  }
}

String _describeColumn(ColumnInfo column) => [
  column.declaredType.isEmpty ? 'untyped' : column.declaredType,
  if (column.isNotNull) 'NOT NULL',
  if (column.isPrimaryKey) 'PRIMARY KEY ${column.primaryKeyPosition}',
  if (column.defaultSql != null) 'DEFAULT ${column.defaultSql}',
  if (column.generated != null) 'GENERATED ${column.generated!.name.toUpperCase()}',
].join(' ');

List<SchemaDifference> _compareFacts(String table, _TableFacts expected, _TableFacts actual) {
  final differences = <SchemaDifference>[];
  final expectedColumns = {for (final column in expected.columns) column.name: column};
  final actualColumns = {for (final column in actual.columns) column.name: column};
  for (final MapEntry(key: name, value: column) in expectedColumns.entries) {
    final found = actualColumns[name];
    if (found == null) {
      differences.add(
        SchemaDifference(
          table: table,
          kind: DifferenceKind.missingColumn,
          subject: name,
          expected: _describeColumn(column),
          actual: null,
        ),
      );
    } else if (found != column) {
      differences.add(
        SchemaDifference(
          table: table,
          kind: DifferenceKind.columnDiffers,
          subject: name,
          expected: _describeColumn(column),
          actual: _describeColumn(found),
        ),
      );
    }
  }
  for (final MapEntry(key: name, value: column) in actualColumns.entries) {
    if (!expectedColumns.containsKey(name)) {
      differences.add(
        SchemaDifference(
          table: table,
          kind: DifferenceKind.unexpectedColumn,
          subject: name,
          expected: null,
          actual: _describeColumn(column),
        ),
      );
    }
  }
  if (!_sameSet(expected.keys, actual.keys)) {
    differences.add(
      SchemaDifference(
        table: table,
        kind: DifferenceKind.keyDiffers,
        expected: (expected.keys.toList()..sort()).join(', '),
        actual: (actual.keys.toList()..sort()).join(', '),
      ),
    );
  }
  if (!_sameSet(expected.foreignKeys, actual.foreignKeys)) {
    differences.add(
      SchemaDifference(
        table: table,
        kind: DifferenceKind.foreignKeyDiffers,
        expected: (expected.foreignKeys.toList()..sort()).join('; '),
        actual: (actual.foreignKeys.toList()..sort()).join('; '),
      ),
    );
  }
  for (final MapEntry(key: name, value: sql) in expected.indexes.entries) {
    final found = actual.indexes[name];
    if (found == null) {
      differences.add(
        SchemaDifference(table: table, kind: DifferenceKind.missingIndex, subject: name, expected: sql, actual: null),
      );
    } else if (found != sql) {
      differences.add(
        SchemaDifference(table: table, kind: DifferenceKind.indexDiffers, subject: name, expected: sql, actual: found),
      );
    }
  }
  for (final MapEntry(key: name, value: sql) in actual.indexes.entries) {
    if (!expected.indexes.containsKey(name)) {
      differences.add(
        SchemaDifference(
          table: table,
          kind: DifferenceKind.unexpectedIndex,
          subject: name,
          expected: null,
          actual: sql,
        ),
      );
    }
  }
  if (expected.options != null && actual.options != null && expected.options != actual.options) {
    differences.add(
      SchemaDifference(
        table: table,
        kind: DifferenceKind.optionDiffers,
        expected: expected.options!.isEmpty ? 'without options' : expected.options,
        actual: actual.options!.isEmpty ? 'without options' : actual.options,
      ),
    );
  }
  if (differences.isEmpty && expected.sql != actual.sql) {
    differences.add(
      SchemaDifference(
        table: table,
        kind: DifferenceKind.definitionDiffers,
        expected: expected.sql,
        actual: actual.sql,
      ),
    );
  }
  return differences;
}

bool _sameSet(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);
