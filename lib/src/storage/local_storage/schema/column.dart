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

part of 'schema.dart';

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
  List<Object?> get props => [
    type,
    notNull,
    isPrimary,
    unique,
    autoincrement,
    collation,
    defaultSql,
    references,
    generated,
  ];
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
