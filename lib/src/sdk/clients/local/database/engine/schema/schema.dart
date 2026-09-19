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

import '../database.dart';
import '../query/sort_order.dart';

part 'column.dart';
part 'primary_key.dart';
part 'unique.dart';
part 'check.dart';
part 'foreign_key.dart';
part 'index.dart';
part 'validation.dart';

String _quoteIdentifier(String identifier) => '"${identifier.replaceAll('"', '""')}"';

String _renderAction(ReferentialAction action) => switch (action) {
  ReferentialAction.noAction => 'NO ACTION',
  ReferentialAction.restrict => 'RESTRICT',
  ReferentialAction.cascade => 'CASCADE',
  ReferentialAction.setNull => 'SET NULL',
  ReferentialAction.setDefault => 'SET DEFAULT',
};

String _renderCollation(Collation collation) => switch (collation) {
  Collation.binary => 'BINARY',
  Collation.noCase => 'NOCASE',
  Collation.rtrim => 'RTRIM',
};

String _renderDeferral(Deferral deferral) => switch (deferral) {
  Deferral.initiallyImmediate => 'DEFERRABLE',
  Deferral.initiallyDeferred => 'DEFERRABLE INITIALLY DEFERRED',
};

String _quoteText(String text) => "'${text.replaceAll("'", "''")}'";

String _renderLiteral(DatabaseType value) => switch (value) {
  Nil() => 'NULL',
  Integer(value: final integer) => '$integer',
  Real(value: final real) => '$real',
  Varchar(value: final text) => text.split('\u0000').map(_quoteText).join(' || char(0) || '),
  Blob(value: final bytes) => "X'${bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}'",
};

String _renderDefault(ColumnDefault defaultValue) => switch (defaultValue) {
  LiteralDefault(:final value) => _renderLiteral(value),
  ExpressionDefault(:final sql) => sql,
};

bool _isRowidAlias(ColumnDefinition column) => column.isPrimary && column.type == ColumnType.integer;

String _renderColumn(String name, ColumnDefinition column) {
  final parts = <String>[_quoteIdentifier(name), column.type.name.toUpperCase()];
  if (column.isPrimary) {
    parts.add('PRIMARY KEY');
    if (column.autoincrement) parts.add('AUTOINCREMENT');
  }
  if (column.notNull && !_isRowidAlias(column)) parts.add('NOT NULL');
  if (column.unique) parts.add('UNIQUE');
  final collation = column.collation;
  if (collation != null) parts.add('COLLATE ${_renderCollation(collation)}');
  final defaultValue = column.defaultValue;
  if (defaultValue != null) parts.add('DEFAULT (${_renderDefault(defaultValue)})');
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
    if (reference.deferral != null) parts.add(_renderDeferral(reference.deferral!));
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
  if (key.deferral != null) parts.add(_renderDeferral(key.deferral!));
  return parts.join(' ');
}

String _renderIndexColumn(IndexColumn column) {
  final parts = <String>[
    switch (column) {
      NamedIndexColumn(:final name) => _quoteIdentifier(name),
      ExpressionIndexColumn(:final sql) => sql,
    },
  ];
  final collation = column.collation;
  if (collation != null) parts.add('COLLATE ${_renderCollation(collation)}');
  final order = column.order;
  if (order != null) parts.add(order.sql);
  return parts.join(' ');
}

String _renderIndex(String table, TableIndex index) {
  final unique = index.unique ? 'UNIQUE ' : '';
  final columns = index.columns.map(_renderIndexColumn).join(', ');
  final where = index.where != null ? ' WHERE ${index.where}' : '';
  return 'CREATE ${unique}INDEX ${_quoteIdentifier(index.name)} ON ${_quoteIdentifier(table)} ($columns)$where';
}

/// A table exactly as [TableBuilderBase.columns] declared it, ready to render
/// its own `CREATE TABLE` and `CREATE INDEX` statements.
final class DeclaredTable extends Equatable {
  /// Built only by [TableBuilderBase.columns], never by hand: a value assembled
  /// here could hold a combination the builder refuses.
  const DeclaredTable._({
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

  /// This table's columns, by field name, in the order [TableBuilderBase.columns]
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
  /// [TableBuilderBase.columns] refuses one without either.
  final bool withoutRowid;

  /// Whether this table declares a foreign key, on a column or at the table
  /// level. SQLite enforces none of them on a connection that has not run
  /// `PRAGMA foreign_keys = ON`, which [LocalDatabase] runs on every connection
  /// it opens.
  bool get usesForeignKeys => foreignKeys.isNotEmpty || columns.values.any((column) => column.references != null);

  /// Checks that [tables], declared for one database, agree with each other,
  /// which [TableBuilderBase.columns] cannot see from inside a single table.
  ///
  /// Throws an [ArgumentError] listing every foreign key that points at a
  /// table [tables] does not declare, at a column it does not have, at a
  /// different number of columns than the key holds, or at columns that are
  /// neither the primary key nor unique. SQLite accepts each of those when
  /// the table is created and fails at the first write, with
  /// `foreign key mismatch` or `no such table`.
  static void checkTogether(List<DeclaredTable> tables) {
    final problems = _crossTableProblems(tables);
    if (problems.isNotEmpty) throw ArgumentError(problems.join('\n'));
  }

  /// The `CREATE TABLE` statement first, then one `CREATE INDEX` per entry
  /// of [indexes], ready for [LocalDatabase.execute], one statement per
  /// call, inside `onCreate` or `onUpgrade`.
  ///
  /// The order of several tables does not matter: SQLite resolves the table
  /// a foreign key points at when a row is written, not when the table is
  /// created. Rendered again on every call.
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

  /// The `ALTER TABLE` statement that adds [column] to a table that already
  /// exists in a file.
  ///
  /// Throws a [StateError] naming the reason when SQLite cannot add such a
  /// column: it is a primary key or unique, it refuses NULL and has no literal
  /// default, it is a foreign key with a default, or its default is an
  /// expression.
  String addColumnStatement(String column) {
    final definition = columns[column] ?? (throw ArgumentError.value(column, 'column', 'Not a column of $name.'));
    final defaultValue = definition.defaultValue;
    final reason = switch (definition) {
      ColumnDefinition(isPrimary: true) || ColumnDefinition(unique: true) => 'a key or unique column',
      ColumnDefinition(notNull: true) when defaultValue == null => 'it refuses NULL and has no default',
      ColumnDefinition(references: != null) when defaultValue != null => 'a foreign key cannot take a default',
      ColumnDefinition() when defaultValue is ExpressionDefault => 'its default is an expression',
      _ => null,
    };
    if (reason != null) throw StateError(reason);
    return 'ALTER TABLE ${_quoteIdentifier(name)} ADD COLUMN ${_renderColumn(column, definition)}';
  }

  @override
  List<Object?> get props => [
    name,
    columns.keys.toList(),
    columns.values.toList(),
    primaryKey,
    uniques,
    checks,
    foreignKeys,
    indexes,
    strict,
    withoutRowid,
  ];
}

/// A SQLite table under construction, closed by [TableBuilderBase.columns].
///
/// Mirrors the Postgres `Table`/`TableBuilder` this package already writes
/// elsewhere, trimmed to what SQLite actually has: no row-level security, no
/// `GRANT`/`REVOKE` (SQLite has no per-role privilege at all, a database
/// file's permissions are the operating system's), no `EXCLUDE` constraint
/// (needs `GiST`, which SQLite does not implement), no `fillfactor`. In
/// their place, [TableBuilder.strict] and [withoutRowid] carry the two
/// table-level knobs that are actually SQLite's own.
///
/// ```dart
/// final table = TableBuilder('todos')
///     .checks((ck) => [ck.expression("length(title) > 0")])
///     .indexes((i) => [i.name('todos_done_idx').columns(const [IndexColumn.named('done')])])
///     .columns((c) => {
///       'id': c.integer().autoincrement(),
///       'title': c.text().isNullable(false),
///       'done': c.integer().isNullable(false).default_(DatabaseType.boolean(false)),
///     });
///
/// onCreate: (db, version) async {
///   for (final statement in table.statements) {
///     await db.execute(statement);
///   }
/// }
/// ```
sealed class TableBuilderBase<Self extends TableBuilderBase<Self, Columns>, Columns extends ColumnFactory> {
  TableBuilderBase._(this._name, this._columns);

  final String _name;
  final Columns _columns;
  PrimaryKeyConstraint? _primaryKey;
  List<UniqueConstraint> _uniques = const [];
  List<CheckConstraint> _checks = const [];
  List<TableForeignKey> _foreignKeys = const [];
  List<TableIndex> _indexes = const [];
  bool _withoutRowid = false;

  bool get _isStrict;

  Self get _self => this as Self;

  Self _carrying(TableBuilderBase<dynamic, ColumnFactory> other) {
    _primaryKey = other._primaryKey;
    _uniques = other._uniques;
    _checks = other._checks;
    _foreignKeys = other._foreignKeys;
    _indexes = other._indexes;
    _withoutRowid = other._withoutRowid;
    return _self;
  }

  /// Makes this table's primary key span every column named, rather than a
  /// single column.
  Self primaryKey(TablePrimaryKeyBuilder Function(TablePrimaryKeyFactory pk) build) {
    _primaryKey = build(const TablePrimaryKeyFactory())._build();
    return _self;
  }

  /// The `UNIQUE` constraints this table carries beyond a single column's
  /// own [ColumnBuilder.unique].
  Self uniques(List<TableUniqueBuilder> Function(TableUniqueFactory factory) build) {
    _uniques = build(const TableUniqueFactory()).map((constraint) => constraint._build()).toList();
    return _self;
  }

  /// The `CHECK` constraints this table carries, each free to read as many
  /// columns as it names.
  Self checks(List<TableCheckBuilder> Function(TableCheckFactory factory) build) {
    _checks = build(const TableCheckFactory()).map((constraint) => constraint._build()).toList();
    return _self;
  }

  /// The `FOREIGN KEY` constraints this table carries beyond a single
  /// column's own [ColumnBuilder.references].
  Self foreignKeys(List<TableForeignKeyBuilder> Function(TableForeignKeyFactory factory) build) {
    _foreignKeys = build(const TableForeignKeyFactory()).map((constraint) => constraint._build()).toList();
    return _self;
  }

  /// The indexes this table carries.
  Self indexes(List<TableIndexBuilder> Function(TableIndexFactory factory) build) {
    _indexes = build(const TableIndexFactory()).map((index) => index._build()).toList();
    return _self;
  }

  /// Skips the hidden `rowid` column every ordinary table otherwise
  /// carries. Requires an explicit [primaryKey] or a single-column
  /// [ColumnBuilder.isPrimary]: SQLite refuses a `WITHOUT ROWID` table
  /// without either, a rule [columns] leaves to SQLite's own error.
  Self withoutRowid([bool value = true]) {
    _withoutRowid = value;
    return _self;
  }

  /// Closes this table, ready for [DeclaredTable.statements] to render.
  ///
  /// Every column of a composite [primaryKey] is made `NOT NULL`, because
  /// SQLite lets a rowid table store null in a primary key column that does
  /// not say otherwise.
  ///
  /// Throws an [ArgumentError] when [primaryKey] was called and a column
  /// also calls [ColumnBuilder.isPrimary]: a table has exactly one primary
  /// key, single-column or composite, never both spellings on the same
  /// table.
  ///
  /// Throws an [ArgumentError], naming the table and the column, for each
  /// declaration SQLite accepts when it creates the table and then does not
  /// do what was written: a `NULL` default on a `NOT NULL` column, and a
  /// foreign key action that sets a `NOT NULL` column to null, a column
  /// without a default to its default, or a generated column to anything.
  /// An `AUTOINCREMENT` column that is not the primary key and an `ANY` column
  /// outside a `STRICT` table are not refused here because they cannot be
  /// written: [IntegerColumnBuilder.autoincrement] makes its column the primary
  /// key and only [StrictColumnFactory] offers [StrictColumnFactory.any]. Every problem found is listed in the one
  /// error. What SQLite already refuses clearly at `CREATE TABLE` is left to
  /// it.
  DeclaredTable columns(ColumnMap Function(Columns c) build) {
    final resolved = <String, ColumnDefinition>{
      for (final entry in build(_columns).entries) entry.key: entry.value.build(),
    };

    if (_primaryKey != null && resolved.values.any((column) => column.isPrimary)) {
      throw ArgumentError(
        '"$_name" names a composite primary key and also carries a column-level isPrimary(). '
        'A table has exactly one primary key: keep the one on the columns it spans, and drop the other.',
      );
    }

    final declared = DeclaredTable._(
      name: _name,
      columns: _refusingNullInCompositeKey(resolved),
      primaryKey: _primaryKey,
      uniques: _uniques,
      checks: _checks,
      foreignKeys: _foreignKeys,
      indexes: _indexes,
      strict: _isStrict,
      withoutRowid: _withoutRowid,
    );
    final problems = declared.problems();
    if (problems.isNotEmpty) throw ArgumentError(problems.join('\n'));
    return declared;
  }

  Map<String, ColumnDefinition> _refusingNullInCompositeKey(Map<String, ColumnDefinition> resolved) {
    final key = _primaryKey;
    if (key == null) return resolved;
    final keyed = key.columns.map(_foldIdentifier).toSet();
    return {
      for (final entry in resolved.entries)
        entry.key: keyed.contains(_foldIdentifier(entry.key)) ? entry.value._refusingNull() : entry.value,
    };
  }
}

/// A SQLite table under construction that SQLite does not type-check, opened
/// by `TableBuilder(name)`. Its columns offer no [StrictColumnFactory.any]:
/// outside a `STRICT` table a column of that type has `NUMERIC` affinity and
/// rewrites the text `'007'` to the integer `7` on the way in.
final class TableBuilder extends TableBuilderBase<TableBuilder, ColumnFactory> {
  /// Opens a table named `name`, closed by [columns].
  TableBuilder(String name) : super._(name, const ColumnFactory());

  @override
  bool get _isStrict => false;

  /// Makes this table enforce its own column types rather than SQLite's
  /// ordinary type affinity rules. Requires SQLite 3.37 or newer.
  ///
  /// Answers a [StrictTableBuilder], the only builder whose columns offer
  /// [StrictColumnFactory.any].
  StrictTableBuilder strict() => StrictTableBuilder._(_name)._carrying(this);
}

/// A `STRICT` SQLite table under construction, opened by [TableBuilder.strict].
final class StrictTableBuilder extends TableBuilderBase<StrictTableBuilder, StrictColumnFactory> {
  StrictTableBuilder._(String name) : super._(name, const StrictColumnFactory._());

  @override
  bool get _isStrict => true;
}
