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

/// A `CREATE TABLE` column's declared type, spelled the way SQLite's own
/// `STRICT` tables take it — the only five keywords a `STRICT` column may
/// name, matching [SqlValue]'s own five storage classes exactly. A non-`STRICT`
/// table accepts the same five keywords too; SQLite just does not enforce
/// them there.
enum ColumnType {
  /// A signed integer, up to 64 bits.
  integer,

  /// A floating point value.
  real,

  /// UTF-8 text.
  text,

  /// Raw bytes.
  blob,

  /// Any storage class at all — the escape hatch `STRICT` needs for a column
  /// with no fixed type. Meaningless outside a `STRICT` table.
  any,
}

/// What happens to a referencing row when the row it points at changes,
/// spelled as `create table` takes it.
enum ReferentialAction {
  /// Nothing special: the same as leaving it out entirely, spelled out for a
  /// column that wants to be explicit about it.
  noAction,

  /// Refuses the change that would strand this row.
  restrict,

  /// Carries the change through to this row.
  cascade,

  /// Sets this row's own column to null.
  setNull,

  /// Sets this row's own column to its declared default.
  setDefault,
}

/// Whether a [GeneratedColumn]'s value is computed once and stored like any
/// other column, or recomputed on every read instead.
enum GeneratedStorage {
  /// Computed once, at write time, and kept on disk.
  stored,

  /// Recomputed on every read. Stores nothing.
  virtual,
}

/// Which way an [IndexColumn] sorts. Ascending, SQLite's own default, when
/// left out entirely.
enum IndexOrder {
  /// Smallest first.
  asc,

  /// Largest first.
  desc,
}

/// A foreign key, from a column to another table's column.
///
/// Left off [column], SQLite resolves to the referenced table's own primary
/// key on its own — nothing here has to guess a name for it the way a
/// Rails-style convention would.
final class ColumnReference extends Equatable {
  /// Wraps every field a [ColumnBuilder.references] or [TableForeignKeyBuilder] call resolved.
  const ColumnReference({
    required this.table,
    this.column,
    this.onDelete,
    this.onUpdate,
    this.deferrable = false,
    this.initiallyDeferred = false,
  });

  /// The table this column points at.
  final String table;

  /// The column of [table] this column points at. Its primary key when left
  /// out.
  final String? column;

  /// What happens to this row when the referenced row is deleted. Nothing
  /// special when left out.
  final ReferentialAction? onDelete;

  /// What happens to this row when the referenced row's key changes.
  /// Nothing special when left out.
  final ReferentialAction? onUpdate;

  /// Whether this constraint can be checked at the end of the transaction
  /// rather than immediately. SQLite enforces every other constraint
  /// immediately; a foreign key is the one this applies to.
  final bool deferrable;

  /// Whether a deferrable constraint checks at the end of the transaction by
  /// default. Meaningless when [deferrable] is `false`.
  final bool initiallyDeferred;

  @override
  List<Object?> get props => [table, column, onDelete, onUpdate, deferrable, initiallyDeferred];
}

/// A column whose value SQLite computes from the rest of the row, rather
/// than one a caller ever writes.
final class GeneratedColumn extends Equatable {
  /// Wraps every field a [ColumnBuilder.generated] call resolved.
  const GeneratedColumn({required this.expression, required this.storage});

  /// The SQL expression this column computes, in terms of this table's
  /// other columns.
  ///
  /// Nothing here validates it, the same choice [ColumnBuilder.default_]
  /// makes for raw SQL no closed vocabulary covers.
  final String expression;

  /// Whether the value is computed once and stored, or recomputed on every
  /// read.
  final GeneratedStorage storage;

  @override
  List<Object?> get props => [expression, storage];
}

/// A column exactly as a [ColumnBuilder] resolved it, read by
/// [DeclaredTable] to render its own `CREATE TABLE`.
final class ColumnDefinition extends Equatable {
  /// Wraps every field a [ColumnBuilder.build] call resolved.
  const ColumnDefinition({
    required this.type,
    required this.notNull,
    required this.isPrimary,
    required this.unique,
    required this.autoincrement,
    this.collation,
    this.defaultSql,
    this.references,
    this.generated,
  });

  /// The type this column holds.
  final ColumnType type;

  /// Whether this column refuses a null value.
  final bool notNull;

  /// Whether this column is the table's (single-column) primary key.
  final bool isPrimary;

  /// Whether this column refuses a value another row already holds.
  final bool unique;

  /// Whether this column's implicit rowid grows on its own. Meaningless
  /// unless [isPrimary] and [type] is [ColumnType.integer].
  final bool autoincrement;

  /// The collating sequence this column sorts and compares under. SQLite's
  /// own default, `BINARY`, when left out.
  final String? collation;

  /// A raw SQL expression this column takes when a row does not give it
  /// one. Null when it takes none.
  ///
  /// Nothing here validates it, the same choice pylon makes for every other
  /// raw SQL fragment a caller supplies — a `where` clause, a `having`
  /// clause.
  final String? defaultSql;

  /// The foreign key this column carries. Null when it carries none.
  final ColumnReference? references;

  /// How this column's value is computed from the rest of the row. Null
  /// when it is an ordinary column.
  final GeneratedColumn? generated;

  @override
  List<Object?> get props => [type, notNull, isPrimary, unique, autoincrement, collation, defaultSql, references, generated];
}

/// A column under construction, opened by one of [ColumnFactory]'s type
/// methods and refined by whichever modifier applies, in any order, closed
/// by [build].
///
/// Unlike Postgres, SQLite has no per-role privilege to guard and no
/// server-side identity sequence to configure, so this stays far smaller
/// than the Postgres builder it mirrors: no `array`, no `identity` options,
/// no geometric or network types. [CollatableColumnBuilder] and
/// [AutoincrementCapableColumnBuilder] play the same narrowing role
/// `CollatableColumnBuilder`/`IdentityCapableColumnBuilder` do there, kept to
/// the two SQLite features that only make sense on one type each.
final class ColumnBuilder {
  ColumnBuilder._(this._type);

  final ColumnType _type;
  bool _isPrimary = false;
  bool _isNullable = true;
  bool _unique = false;
  bool _autoincrement = false;
  String? _collation;
  String? _defaultSql;
  ColumnReference? _references;
  GeneratedColumn? _generated;

  /// Makes this column the table's primary key, which also refuses a null
  /// value.
  ColumnBuilder isPrimary() {
    _isPrimary = true;
    return this;
  }

  /// Whether this column accepts a null value. Refuses one when passed
  /// `false`. Accepts one otherwise, including when called with no
  /// argument.
  ColumnBuilder isNullable([bool value = true]) {
    _isNullable = value;
    return this;
  }

  /// Whether this column refuses a value another row already holds.
  ColumnBuilder unique() {
    _unique = true;
    return this;
  }

  /// A raw SQL expression this column takes when a row does not give it
  /// one.
  ///
  /// Nothing here validates it, the same choice pylon makes for every other
  /// raw SQL fragment a caller supplies.
  ColumnBuilder default_(String sql) {
    _defaultSql = sql;
    return this;
  }

  /// Makes this column a foreign key, pointing at another table's column.
  ColumnBuilder references(ColumnReference reference) {
    _references = reference;
    return this;
  }

  /// Makes this column computed from the rest of the row, rather than one a
  /// caller ever writes.
  ///
  /// SQLite refuses this alongside [default_] or [references] on the same
  /// column, a rule this does not enforce, the same as every other
  /// cross-field rule an author is expected to hold.
  ColumnBuilder generated(GeneratedColumn options) {
    _generated = options;
    return this;
  }

  /// This column's options, exactly as [TableBuilder.columns] reads them
  /// once its own callback returns.
  ColumnDefinition build() => ColumnDefinition(
    type: _type,
    notNull: _isPrimary || !_isNullable,
    isPrimary: _isPrimary,
    unique: _unique,
    autoincrement: _autoincrement,
    collation: _collation,
    defaultSql: _defaultSql,
    references: _references,
    generated: _generated,
  );
}

/// A [ColumnType.text] column under construction — the only type
/// [ColumnFactory] opens as this rather than as a bare [ColumnBuilder],
/// since a collating sequence changes how text sorts and compares but says
/// nothing about an integer, a real or a blob.
final class CollatableColumnBuilder extends ColumnBuilder {
  // ignore: use_super_parameters (super's constructor is named `_`, which the shorthand cannot target)
  CollatableColumnBuilder._(ColumnType type) : super._(type);

  @override
  CollatableColumnBuilder isPrimary() {
    super.isPrimary();
    return this;
  }

  @override
  CollatableColumnBuilder isNullable([bool value = true]) {
    super.isNullable(value);
    return this;
  }

  @override
  CollatableColumnBuilder unique() {
    super.unique();
    return this;
  }

  @override
  CollatableColumnBuilder default_(String sql) {
    super.default_(sql);
    return this;
  }

  @override
  CollatableColumnBuilder references(ColumnReference reference) {
    super.references(reference);
    return this;
  }

  @override
  CollatableColumnBuilder generated(GeneratedColumn options) {
    super.generated(options);
    return this;
  }

  /// The collating sequence this column sorts and compares under, by name.
  /// SQLite's own default, `BINARY`, when left out.
  CollatableColumnBuilder collation(String name) {
    _collation = name;
    return this;
  }
}

/// A [ColumnType.integer] column under construction — the only type
/// [ColumnFactory] opens as this rather than as a bare [ColumnBuilder],
/// since `AUTOINCREMENT` is legal only on an `INTEGER PRIMARY KEY`.
final class AutoincrementCapableColumnBuilder extends ColumnBuilder {
  // ignore: use_super_parameters (super's constructor is named `_`, which the shorthand cannot target)
  AutoincrementCapableColumnBuilder._(ColumnType type) : super._(type);

  @override
  AutoincrementCapableColumnBuilder isPrimary() {
    super.isPrimary();
    return this;
  }

  @override
  AutoincrementCapableColumnBuilder isNullable([bool value = true]) {
    super.isNullable(value);
    return this;
  }

  @override
  AutoincrementCapableColumnBuilder unique() {
    super.unique();
    return this;
  }

  @override
  AutoincrementCapableColumnBuilder default_(String sql) {
    super.default_(sql);
    return this;
  }

  @override
  AutoincrementCapableColumnBuilder references(ColumnReference reference) {
    super.references(reference);
    return this;
  }

  @override
  AutoincrementCapableColumnBuilder generated(GeneratedColumn options) {
    super.generated(options);
    return this;
  }

  /// Makes this column's rowid grow on its own, rather than reusing a
  /// smaller id a deleted row left behind.
  ///
  /// `identity column type must be smallint, integer, or bigint` is
  /// Postgres's own words for a sibling rule; SQLite's own version is
  /// narrower still, legal only on a single-column `INTEGER PRIMARY KEY`, a
  /// rule this does not enforce.
  AutoincrementCapableColumnBuilder autoincrement() {
    _autoincrement = true;
    return this;
  }
}

/// Opens a column of one SQLite type, refined by whichever [ColumnBuilder]
/// modifier [TableBuilder.columns]' own callback chains onto it.
///
/// ```dart
/// TableBuilder('todos').columns((c) => {
///   'id': c.integer().isPrimary().autoincrement(),
///   'title': c.text().isNullable(false),
///   'done': c.integer().isNullable(false).default_('0'),
/// });
/// ```
final class ColumnFactory {
  /// Opens no column on its own; each of its methods does.
  const ColumnFactory();

  /// Opens an [ColumnType.integer] column, capable of [AutoincrementCapableColumnBuilder.autoincrement].
  AutoincrementCapableColumnBuilder integer() => AutoincrementCapableColumnBuilder._(ColumnType.integer);

  /// Opens a [ColumnType.real] column.
  ColumnBuilder real() => ColumnBuilder._(ColumnType.real);

  /// Opens a [ColumnType.text] column, collatable by name.
  CollatableColumnBuilder text() => CollatableColumnBuilder._(ColumnType.text);

  /// Opens a [ColumnType.blob] column.
  ColumnBuilder blob() => ColumnBuilder._(ColumnType.blob);

  /// Opens an [ColumnType.any] column — a `STRICT`-table escape hatch for a
  /// column with no fixed type. Meaningless outside a [TableBuilder.strict]
  /// table.
  ColumnBuilder any() => ColumnBuilder._(ColumnType.any);
}

/// What [TableBuilder.columns] takes: a column builder, by the name it holds
/// under, in the order they are declared — the order [DeclaredTable] renders
/// them in.
typedef ColumnMap = Map<String, ColumnBuilder>;

/// A composite `PRIMARY KEY`, spanning every column named.
final class PrimaryKeyConstraint extends Equatable {
  /// Wraps every field a [TablePrimaryKeyBuilder] call resolved.
  const PrimaryKeyConstraint({required this.columns, this.name});

  /// The columns that, together, identify a row. Every one of them is
  /// refused a null value.
  final List<String> columns;

  /// The name this constraint is created under. SQLite picks one on its
  /// own when left out.
  final String? name;

  @override
  List<Object?> get props => [columns, name];
}

/// Opens a table's composite primary key, closed by
/// [TablePrimaryKeyBuilder.name] or read directly once
/// [TableBuilder.primaryKey]'s own callback returns.
final class TablePrimaryKeyFactory {
  /// Opens no primary key on its own; [columns] does.
  const TablePrimaryKeyFactory();

  /// The columns that, together, identify a row. Every one of them is
  /// refused a null value.
  TablePrimaryKeyBuilder columns(List<String> columns) => TablePrimaryKeyBuilder._(columns);
}

/// A table's composite primary key under construction, opened by
/// [TablePrimaryKeyFactory.columns].
final class TablePrimaryKeyBuilder {
  TablePrimaryKeyBuilder._(this._columns);

  final List<String> _columns;
  String? _name;

  /// The name this constraint is created under. SQLite picks one on its
  /// own when left out.
  TablePrimaryKeyBuilder name(String name) {
    _name = name;
    return this;
  }

  PrimaryKeyConstraint _build() => PrimaryKeyConstraint(columns: _columns, name: _name);
}

/// A `UNIQUE` constraint spanning one or several columns at once.
final class UniqueConstraint extends Equatable {
  /// Wraps every field a [TableUniqueBuilder] call resolved.
  const UniqueConstraint({required this.columns, this.name});

  /// The columns that, together, must not repeat across two rows.
  final List<String> columns;

  /// The name this constraint is created under. SQLite picks one on its
  /// own when left out.
  final String? name;

  @override
  List<Object?> get props => [columns, name];
}

/// Opens a `UNIQUE` constraint, closed by [TableUniqueBuilder.name] or read
/// directly once [TableBuilder.uniques]' own callback returns.
final class TableUniqueFactory {
  /// Opens no constraint on its own; [columns] does.
  const TableUniqueFactory();

  /// The columns that, together, must not repeat across two rows.
  TableUniqueBuilder columns(List<String> columns) => TableUniqueBuilder._(columns);
}

/// A `UNIQUE` constraint under construction, opened by
/// [TableUniqueFactory.columns].
final class TableUniqueBuilder {
  TableUniqueBuilder._(this._columns);

  final List<String> _columns;
  String? _name;

  /// The name this constraint is created under. SQLite picks one on its
  /// own when left out.
  TableUniqueBuilder name(String name) {
    _name = name;
    return this;
  }

  UniqueConstraint _build() => UniqueConstraint(columns: _columns, name: _name);
}

/// A `CHECK` constraint, carried by the table rather than by one column, so
/// it may read several at once.
final class CheckConstraint extends Equatable {
  /// Wraps every field a [TableCheckBuilder] call resolved.
  const CheckConstraint({required this.expression, this.name});

  /// The raw SQL predicate every row must satisfy.
  ///
  /// Nothing here validates it, the same choice [ColumnBuilder.default_]
  /// makes for raw SQL no closed vocabulary covers.
  final String expression;

  /// The name this constraint is created under. SQLite picks one on its
  /// own when left out.
  final String? name;

  @override
  List<Object?> get props => [expression, name];
}

/// Opens a `CHECK` constraint, closed by [TableCheckBuilder.name] or read
/// directly once [TableBuilder.checks]' own callback returns.
final class TableCheckFactory {
  /// Opens no constraint on its own; [expression] does.
  const TableCheckFactory();

  /// The raw SQL predicate every row must satisfy.
  TableCheckBuilder expression(String expression) => TableCheckBuilder._(expression);
}

/// A `CHECK` constraint under construction, opened by
/// [TableCheckFactory.expression].
final class TableCheckBuilder {
  TableCheckBuilder._(this._expression);

  final String _expression;
  String? _name;

  /// The name this constraint is created under. SQLite picks one on its
  /// own when left out.
  TableCheckBuilder name(String name) {
    _name = name;
    return this;
  }

  CheckConstraint _build() => CheckConstraint(expression: _expression, name: _name);
}

/// A table-level `FOREIGN KEY` constraint spanning one or several columns at
/// once.
final class TableForeignKey extends Equatable {
  /// Wraps every field a [TableForeignKeyBuilder] call resolved.
  const TableForeignKey({
    required this.columns,
    required this.referencedTable,
    this.referencedColumns,
    this.onDelete,
    this.onUpdate,
    this.deferrable = false,
    this.initiallyDeferred = false,
    this.name,
  });

  /// The columns of this table that, together, form the key.
  final List<String> columns;

  /// The table [columns] points at.
  final String referencedTable;

  /// The columns of [referencedTable] this key points at, in the same order
  /// as [columns]. Its primary key when left out.
  final List<String>? referencedColumns;

  /// What happens to this row when the referenced row is deleted. Nothing
  /// special when left out.
  final ReferentialAction? onDelete;

  /// What happens to this row when the referenced row's key changes.
  /// Nothing special when left out.
  final ReferentialAction? onUpdate;

  /// Whether this constraint can be checked at the end of the transaction
  /// rather than immediately.
  final bool deferrable;

  /// Whether a deferrable constraint checks at the end of the transaction by
  /// default. Meaningless when [deferrable] is `false`.
  final bool initiallyDeferred;

  /// The name this constraint is created under. SQLite picks one on its
  /// own when left out.
  final String? name;

  @override
  List<Object?> get props => [
    columns,
    referencedTable,
    referencedColumns,
    onDelete,
    onUpdate,
    deferrable,
    initiallyDeferred,
    name,
  ];
}

/// Opens a table-level `FOREIGN KEY` constraint, closed once
/// [TableForeignKeyBuilder.references] has named the table it points at and
/// [TableBuilder.foreignKeys]' own callback returns.
final class TableForeignKeyFactory {
  /// Opens no constraint on its own; [columns] does.
  const TableForeignKeyFactory();

  /// The columns of this table that, together, form the key.
  TableForeignKeyBuilder columns(List<String> columns) => TableForeignKeyBuilder._(columns);
}

/// A table-level `FOREIGN KEY` constraint under construction, opened by
/// [TableForeignKeyFactory.columns].
final class TableForeignKeyBuilder {
  TableForeignKeyBuilder._(this._columns);

  final List<String> _columns;
  String? _referencedTable;
  List<String>? _referencedColumns;
  ReferentialAction? _onDelete;
  ReferentialAction? _onUpdate;
  bool _deferrable = false;
  bool _initiallyDeferred = false;
  String? _name;

  /// The table [TableForeignKeyFactory.columns] points at, and which of its
  /// columns, in the same order. Its primary key when [referencedColumns]
  /// is left out.
  TableForeignKeyBuilder references(String table, [List<String>? referencedColumns]) {
    _referencedTable = table;
    _referencedColumns = referencedColumns;
    return this;
  }

  /// What happens to this row when the referenced row is deleted. Nothing
  /// special when left out.
  TableForeignKeyBuilder onDelete(ReferentialAction action) {
    _onDelete = action;
    return this;
  }

  /// What happens to this row when the referenced row's key changes.
  /// Nothing special when left out.
  TableForeignKeyBuilder onUpdate(ReferentialAction action) {
    _onUpdate = action;
    return this;
  }

  /// Lets this constraint wait until the end of its transaction to be
  /// checked, rather than immediately.
  TableForeignKeyBuilder deferrable([bool initiallyDeferred = false]) {
    _deferrable = true;
    _initiallyDeferred = initiallyDeferred;
    return this;
  }

  /// The name this constraint is created under. SQLite picks one on its
  /// own when left out.
  TableForeignKeyBuilder name(String name) {
    _name = name;
    return this;
  }

  /// This constraint, exactly as [TableBuilder.foreignKeys] reads it once
  /// its own callback returns.
  ///
  /// Throws a [StateError] when [references] was never called: a foreign
  /// key with nothing to point at is refused here, not once
  /// [DeclaredTable.statements] tries to render it.
  TableForeignKey _build() {
    final table = _referencedTable ?? (throw StateError('TableForeignKeyBuilder.references was never called.'));
    return TableForeignKey(
      columns: _columns,
      referencedTable: table,
      referencedColumns: _referencedColumns,
      onDelete: _onDelete,
      onUpdate: _onUpdate,
      deferrable: _deferrable,
      initiallyDeferred: _initiallyDeferred,
      name: _name,
    );
  }
}

/// One column an index covers, spelled out rather than left as a bare name,
/// for an entry that needs a collation or its own sort order.
final class IndexColumn extends Equatable {
  /// Wraps [expression], [collation] and [order] directly, rather than through a builder — this is the leaf entry [TableIndexBuilder.columns] itself takes.
  const IndexColumn(this.expression, {this.collation, this.order});

  /// The raw SQL expression this entry covers, most often a bare column
  /// name.
  ///
  /// Nothing here validates it, the same choice [ColumnBuilder.default_]
  /// makes for raw SQL no closed vocabulary covers — an expression a bare
  /// column name cannot express, `"lower(email)"`, belongs here just as
  /// well as a plain column would.
  final String expression;

  /// The collating sequence this entry sorts and compares under. SQLite's
  /// own default for its type when left out.
  final String? collation;

  /// The order this entry sorts in. Ascending when left out, SQLite's own
  /// default.
  final IndexOrder? order;

  @override
  List<Object?> get props => [expression, collation, order];
}

/// An index exactly as a [TableIndexBuilder] resolved it, read by
/// [DeclaredTable] to render its own `CREATE INDEX`.
final class TableIndex extends Equatable {
  /// Wraps every field a [TableIndexBuilder] call resolved.
  const TableIndex({required this.name, required this.columns, this.unique = false, this.where});

  /// The name this index is created under.
  final String name;

  /// The columns this index covers, in the order SQLite will list them, at
  /// least one.
  final List<IndexColumn> columns;

  /// Whether this index refuses a row whose covered columns match one
  /// already stored.
  final bool unique;

  /// Restricts the index to the rows where this raw SQL predicate holds,
  /// making it a partial index. Covers every row when left out.
  ///
  /// Nothing here validates it, the same choice [ColumnBuilder.default_]
  /// makes for raw SQL no closed vocabulary covers.
  final String? where;

  @override
  List<Object?> get props => [name, columns, unique, where];
}

/// Opens an index, named `name`, closed once [TableIndexBuilder.columns] has
/// named what it covers and [TableBuilder.indexes]' own callback returns.
final class TableIndexFactory {
  /// Opens no index on its own; [name] does.
  const TableIndexFactory();

  /// The name this index is created under.
  TableIndexBuilder name(String name) => TableIndexBuilder._(name);
}

/// An index under construction, opened by [TableIndexFactory.name].
final class TableIndexBuilder {
  TableIndexBuilder._(this._name);

  final String _name;
  List<IndexColumn>? _columns;
  bool _unique = false;
  String? _where;

  /// The columns this index covers, in the order SQLite will list them, at
  /// least one.
  ///
  /// A bare [String] is read as an [IndexColumn.expression] with no
  /// collation and no explicit order; reach for [IndexColumn] itself only
  /// when an entry needs one of those.
  TableIndexBuilder columns(List<Object> columns) {
    _columns = columns.map((column) => column is IndexColumn ? column : IndexColumn(column as String)).toList();
    return this;
  }

  /// Refuses a row whose covered columns match one already stored.
  TableIndexBuilder unique() {
    _unique = true;
    return this;
  }

  /// Restricts this index to the rows where this raw SQL predicate holds,
  /// making it a partial index. Covers every row when left out.
  TableIndexBuilder where(String predicate) {
    _where = predicate;
    return this;
  }

  /// This index, exactly as [TableBuilder.indexes] reads it once its own
  /// callback returns.
  ///
  /// Throws a [StateError] when [columns] was never called: an index over
  /// nothing is refused here, not once [DeclaredTable.statements] tries to
  /// render it.
  TableIndex _build() {
    final columns = _columns ?? (throw StateError('TableIndexBuilder.columns was never called.'));
    return TableIndex(name: _name, columns: columns, unique: _unique, where: _where);
  }
}

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
