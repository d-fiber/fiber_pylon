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

import 'package:equatable/equatable.dart';

part 'column.dart';
part 'primary_key.dart';
part 'unique.dart';
part 'check.dart';
part 'foreign_key.dart';
part 'index.dart';

String _quoteIdentifier(String identifier) => '"${identifier.replaceAll('"', '""')}"';

String _renderAction(ReferentialAction action) => switch (action) {
  ReferentialAction.noAction => 'NO ACTION',
  ReferentialAction.restrict => 'RESTRICT',
  ReferentialAction.cascade => 'CASCADE',
  ReferentialAction.setNull => 'SET NULL',
  ReferentialAction.setDefault => 'SET DEFAULT',
};

String _renderColumn(String name, ColumnDefinition column) {
  final parts = <String>[_quoteIdentifier(name), column.type.name.toUpperCase()];
  if (column.isPrimary) {
    parts.add('PRIMARY KEY');
    if (column.autoincrement) parts.add('AUTOINCREMENT');
  }
  if (column.notNull && !column.isPrimary) parts.add('NOT NULL');
  if (column.unique) parts.add('UNIQUE');
  if (column.collation != null) parts.add('COLLATE ${column.collation}');
  if (column.defaultSql != null) parts.add('DEFAULT (${column.defaultSql})');
  final generated = column.generated;
  if (generated != null) {
    final storage = generated.storage == GeneratedStorage.stored ? 'STORED' : 'VIRTUAL';
    parts.add('GENERATED ALWAYS AS (${generated.expression}) $storage');
  }
  final reference = column.references;
  if (reference != null) {
    parts.add('REFERENCES ${_quoteIdentifier(reference.table)}');
    if (reference.column != null) parts.add('(${_quoteIdentifier(reference.column!)})');
    if (reference.onDelete != null) parts.add('ON DELETE ${_renderAction(reference.onDelete!)}');
    if (reference.onUpdate != null) parts.add('ON UPDATE ${_renderAction(reference.onUpdate!)}');
    if (reference.deferrable) {
      parts.add('DEFERRABLE');
      if (reference.initiallyDeferred) parts.add('INITIALLY DEFERRED');
    }
  }
  return parts.join(' ');
}

String _renderPrimaryKey(PrimaryKeyConstraint pk) {
  final prefix = pk.name != null ? 'CONSTRAINT ${_quoteIdentifier(pk.name!)} ' : '';
  return '${prefix}PRIMARY KEY (${pk.columns.map(_quoteIdentifier).join(', ')})';
}

String _renderUnique(UniqueConstraint unique) {
  final prefix = unique.name != null ? 'CONSTRAINT ${_quoteIdentifier(unique.name!)} ' : '';
  return '${prefix}UNIQUE (${unique.columns.map(_quoteIdentifier).join(', ')})';
}

String _renderCheck(CheckConstraint check) {
  final prefix = check.name != null ? 'CONSTRAINT ${_quoteIdentifier(check.name!)} ' : '';
  return '${prefix}CHECK (${check.expression})';
}

String _renderForeignKey(TableForeignKey key) {
  final prefix = key.name != null ? 'CONSTRAINT ${_quoteIdentifier(key.name!)} ' : '';
  final columns = key.columns.map(_quoteIdentifier).join(', ');
  final parts = <String>['${prefix}FOREIGN KEY ($columns) REFERENCES ${_quoteIdentifier(key.referencedTable)}'];
  if (key.referencedColumns != null) {
    parts.add('(${key.referencedColumns!.map(_quoteIdentifier).join(', ')})');
  }
  if (key.onDelete != null) parts.add('ON DELETE ${_renderAction(key.onDelete!)}');
  if (key.onUpdate != null) parts.add('ON UPDATE ${_renderAction(key.onUpdate!)}');
  if (key.deferrable) {
    parts.add('DEFERRABLE');
    if (key.initiallyDeferred) parts.add('INITIALLY DEFERRED');
  }
  return parts.join(' ');
}

String _renderIndex(String table, TableIndex index) {
  final unique = index.unique ? 'UNIQUE ' : '';
  final columns = index.columns
      .map((column) {
        final parts = <String>[column.expression];
        if (column.collation != null) parts.add('COLLATE ${column.collation}');
        if (column.order != null) parts.add(column.order == IndexOrder.desc ? 'DESC' : 'ASC');
        return parts.join(' ');
      })
      .join(', ');
  final where = index.where != null ? ' WHERE ${index.where}' : '';
  return 'CREATE ${unique}INDEX ${_quoteIdentifier(index.name)} ON ${_quoteIdentifier(table)} ($columns)$where';
}

/// A table exactly as [TableBuilder.columns] declared it, ready to render
/// its own `CREATE TABLE` and `CREATE INDEX` statements.
final class DeclaredTable extends Equatable {
  /// Wraps every field a [TableBuilder.columns] call resolved.
  const DeclaredTable({
    required this.name,
    required this.columns,
    this.primaryKey,
    this.uniques = const [],
    this.checks = const [],
    this.foreignKeys = const [],
    this.indexes = const [],
    this.strict = false,
    this.withoutRowid = false,
  });

  /// The name this table is created under.
  final String name;

  /// This table's columns, by field name, in the order [TableBuilder.columns]
  /// gave them.
  final Map<String, ColumnDefinition> columns;

  /// This table's composite primary key. Null when it carries none, or
  /// carries a single-column one on a column instead.
  final PrimaryKeyConstraint? primaryKey;

  /// This table's multi-column `UNIQUE` constraints.
  final List<UniqueConstraint> uniques;

  /// This table's `CHECK` constraints.
  final List<CheckConstraint> checks;

  /// This table's table-level `FOREIGN KEY` constraints.
  final List<TableForeignKey> foreignKeys;

  /// The indexes this table carries.
  final List<TableIndex> indexes;

  /// Whether this table enforces its own column types rather than SQLite's
  /// ordinary type affinity rules. Requires SQLite 3.37 or newer.
  final bool strict;

  /// Whether this table skips the hidden `rowid` column every ordinary
  /// table otherwise carries. A table declared `WITHOUT ROWID` needs an
  /// explicit [primaryKey] or a single-column [ColumnBuilder.isPrimary]:
  /// SQLite refuses one without either.
  final bool withoutRowid;

  /// The `CREATE TABLE` statement first, then one `CREATE INDEX` per entry
  /// of [indexes] — ready for [LocalDatabase.execute], one statement per
  /// call, inside `onCreate`/`onUpgrade`.
  List<String> get statements {
    final lines = <String>[
      for (final entry in columns.entries) _renderColumn(entry.key, entry.value),
      if (primaryKey != null) _renderPrimaryKey(primaryKey!),
      for (final unique in uniques) _renderUnique(unique),
      for (final check in checks) _renderCheck(check),
      for (final key in foreignKeys) _renderForeignKey(key),
    ];
    final options = <String>[if (strict) 'STRICT', if (withoutRowid) 'WITHOUT ROWID'];
    final suffix = options.isEmpty ? '' : ' ${options.join(', ')}';
    final createTable = 'CREATE TABLE ${_quoteIdentifier(name)} (${lines.join(', ')})$suffix';
    return [createTable, for (final index in indexes) _renderIndex(name, index)];
  }

  @override
  List<Object?> get props => [name, columns, primaryKey, uniques, checks, foreignKeys, indexes, strict, withoutRowid];
}

/// A SQLite table under construction, closed by [TableBuilder.columns].
///
/// Mirrors the Postgres `Table`/`TableBuilder` this package already writes
/// elsewhere, trimmed to what SQLite actually has: no row-level security, no
/// `GRANT`/`REVOKE` (SQLite has no per-role privilege at all — a database
/// file's permissions are the operating system's), no `EXCLUDE` constraint
/// (needs `GiST`, which SQLite does not implement), no `fillfactor`. In
/// their place, [strict] and [withoutRowid] carry the two table-level knobs
/// that are actually SQLite's own.
///
/// ```dart
/// final table = TableBuilder('todos')
///     .checks((ck) => [ck.expression("length(title) > 0")])
///     .indexes((i) => [i.name('todos_done_idx').columns(['done'])])
///     .columns((c) => {
///       'id': c.integer().isPrimary().autoincrement(),
///       'title': c.text().isNullable(false),
///       'done': c.integer().isNullable(false).default_('0'),
///     });
///
/// onCreate: (db, version) async {
///   for (final statement in table.statements) {
///     await db.execute(statement);
///   }
/// }
/// ```
final class TableBuilder {
  /// Opens a table named `name`, closed by [columns].
  TableBuilder(this._name);

  final String _name;
  PrimaryKeyConstraint? _primaryKey;
  List<UniqueConstraint> _uniques = const [];
  List<CheckConstraint> _checks = const [];
  List<TableForeignKey> _foreignKeys = const [];
  List<TableIndex> _indexes = const [];
  bool _strict = false;
  bool _withoutRowid = false;

  /// Makes this table's primary key span every column named, rather than a
  /// single column.
  TableBuilder primaryKey(TablePrimaryKeyBuilder Function(TablePrimaryKeyFactory pk) build) {
    _primaryKey = build(const TablePrimaryKeyFactory())._build();
    return this;
  }

  /// The `UNIQUE` constraints this table carries beyond a single column's
  /// own [ColumnBuilder.unique].
  TableBuilder uniques(List<TableUniqueBuilder> Function(TableUniqueFactory factory) build) {
    _uniques = build(const TableUniqueFactory()).map((constraint) => constraint._build()).toList();
    return this;
  }

  /// The `CHECK` constraints this table carries, each free to read as many
  /// columns as it names.
  TableBuilder checks(List<TableCheckBuilder> Function(TableCheckFactory factory) build) {
    _checks = build(const TableCheckFactory()).map((constraint) => constraint._build()).toList();
    return this;
  }

  /// The `FOREIGN KEY` constraints this table carries beyond a single
  /// column's own [ColumnBuilder.references].
  TableBuilder foreignKeys(List<TableForeignKeyBuilder> Function(TableForeignKeyFactory factory) build) {
    _foreignKeys = build(const TableForeignKeyFactory()).map((constraint) => constraint._build()).toList();
    return this;
  }

  /// The indexes this table carries.
  TableBuilder indexes(List<TableIndexBuilder> Function(TableIndexFactory factory) build) {
    _indexes = build(const TableIndexFactory()).map((index) => index._build()).toList();
    return this;
  }

  /// Makes this table enforce its own column types rather than SQLite's
  /// ordinary type affinity rules. Requires SQLite 3.37 or newer.
  TableBuilder strict([bool value = true]) {
    _strict = value;
    return this;
  }

  /// Skips the hidden `rowid` column every ordinary table otherwise
  /// carries. Requires an explicit [primaryKey] or a single-column
  /// [ColumnBuilder.isPrimary]: SQLite refuses a `WITHOUT ROWID` table
  /// without either, a rule this does not enforce.
  TableBuilder withoutRowid([bool value = true]) {
    _withoutRowid = value;
    return this;
  }

  /// Closes this table, ready for [DeclaredTable.statements] to render.
  ///
  /// Throws an [ArgumentError] when [primaryKey] was called and a column
  /// also calls [ColumnBuilder.isPrimary]: a table has exactly one primary
  /// key, single-column or composite, never both spellings on the same
  /// table.
  DeclaredTable columns(ColumnMap Function(ColumnFactory c) build) {
    final resolved = <String, ColumnDefinition>{
      for (final entry in build(const ColumnFactory()).entries) entry.key: entry.value.build(),
    };

    if (_primaryKey != null && resolved.values.any((column) => column.isPrimary)) {
      throw ArgumentError(
        '"$_name" names a composite primary key and also carries a column-level isPrimary(). '
        'A table has exactly one primary key: keep the one on the columns it spans, and drop the other.',
      );
    }

    return DeclaredTable(
      name: _name,
      columns: resolved,
      primaryKey: _primaryKey,
      uniques: _uniques,
      checks: _checks,
      foreignKeys: _foreignKeys,
      indexes: _indexes,
      strict: _strict,
      withoutRowid: _withoutRowid,
    );
  }
}
