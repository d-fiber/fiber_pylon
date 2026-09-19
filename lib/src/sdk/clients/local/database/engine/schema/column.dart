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
/// `STRICT` tables take it: the only five keywords a `STRICT` column may
/// name, matching [Value]'s own five storage classes exactly. A non-`STRICT`
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

  /// Any storage class at all, kept exactly as written. The escape hatch
  /// `STRICT` needs for a column with no fixed type.
  ///
  /// Outside a `STRICT` table SQLite gives the keyword `ANY` numeric affinity
  /// and rewrites the text `'007'` into the integer `7`, so
  /// [TableBuilder.columns] refuses it there.
  any,
}

/// A collating sequence SQLite ships with, which decides how a text column
/// sorts and compares.
///
/// SQLite through sqflite offers no way to register another one, so this is
/// the complete list.
enum Collation {
  /// Compares the raw bytes of two texts. SQLite's own default.
  binary,

  /// Compares like [binary], except that the 26 upper-case ASCII letters
  /// count as their lower-case counterparts. Letters outside ASCII keep their
  /// case.
  noCase,

  /// Compares like [binary], except that trailing spaces are ignored.
  rtrim,
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

/// When a deferrable foreign key is checked.
///
/// A foreign key that carries no [Deferral] is not deferrable: SQLite checks
/// it after every statement, and no transaction can postpone that.
enum Deferral {
  /// Deferrable, and checked after every statement unless a transaction asks
  /// to postpone it.
  initiallyImmediate,

  /// Deferrable, and checked when the transaction commits.
  initiallyDeferred,
}

/// Whether a [GeneratedColumn]'s value is computed once and stored like any
/// other column, or recomputed on every read instead.
enum GeneratedStorage {
  /// Computed once, at write time, and kept on disk.
  stored,

  /// Recomputed on every read. Stores nothing.
  virtual,
}

/// The value a column takes when a row does not give it one: either a
/// literal [Value] or a raw SQL expression.
sealed class ColumnDefault extends Equatable {
  const ColumnDefault();
}

/// A default that is one fixed value.
///
/// Rendered as the SQL literal of [value], so a [Varchar] is quoted and a
/// [Blob] is spelled in hexadecimal without the caller writing either.
final class LiteralDefault extends ColumnDefault {
  /// The default [value].
  const LiteralDefault(this.value);

  /// The value a row takes when it gives none.
  final Value value;

  @override
  List<Object?> get props => [value];
}

/// A default computed by a raw SQL expression.
///
/// Nothing here validates it, the same choice made for every other raw SQL
/// fragment a caller supplies.
final class ExpressionDefault extends ColumnDefault {
  /// The default computed by [sql].
  const ExpressionDefault(this.sql);

  /// The SQL expression evaluated for each row that gives no value.
  final String sql;

  @override
  List<Object?> get props => [sql];
}

/// A foreign key, from a column to another table's column.
///
/// Left off [column], SQLite resolves to the referenced table's own primary
/// key on its own, so nothing here has to guess a name for it.
final class ColumnReference extends Equatable {
  /// Wraps every field a [ColumnBuilder.references] or [TableForeignKeyBuilder] call resolved.
  const ColumnReference({required this.table, this.column, this.onDelete, this.onUpdate, this.deferral});

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

  /// When this constraint is checked, if it may be checked later than the
  /// statement that broke it. Not deferrable when left out.
  final Deferral? deferral;

  @override
  List<Object?> get props => [table, column, onDelete, onUpdate, deferral];
}

/// A column whose value SQLite computes from the rest of the row, rather
/// than one a caller ever writes.
final class GeneratedColumn extends Equatable {
  /// Wraps every field a [ColumnBuilder.generated] call resolved.
  const GeneratedColumn({required this.expression, required this.storage});

  /// The SQL expression this column computes, in terms of this table's
  /// other columns.
  ///
  /// Nothing here validates it, the same choice [ColumnBuilder.defaultExpression]
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
  /// Built only by [ColumnBuilder.build], never by hand: a value assembled
  /// here could hold a combination the builder refuses.
  const ColumnDefinition._({
    required this.type,
    required this.notNull,
    required this.isPrimary,
    required this.unique,
    required this.autoincrement,
    this.collation,
    this.defaultValue,
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

  /// Whether this column's rowid grows on its own. It is only ever true
  /// together with [isPrimary], since [IntegerColumnBuilder.autoincrement]
  /// makes the column the primary key.
  final bool autoincrement;

  /// The collating sequence this column sorts and compares under.
  /// [Collation.binary], SQLite's own default, when left out.
  final Collation? collation;

  /// What this column takes when a row does not give it a value. Null when
  /// it takes none.
  final ColumnDefault? defaultValue;

  /// The foreign key this column carries. Null when it carries none.
  final ColumnReference? references;

  /// How this column's value is computed from the rest of the row. Null
  /// when it is an ordinary column.
  final GeneratedColumn? generated;

  ColumnDefinition _refusingNull() => ColumnDefinition._(
    type: type,
    notNull: true,
    isPrimary: isPrimary,
    unique: unique,
    autoincrement: autoincrement,
    collation: collation,
    defaultValue: defaultValue,
    references: references,
    generated: generated,
  );

  @override
  List<Object?> get props => [
    type,
    notNull,
    isPrimary,
    unique,
    autoincrement,
    collation,
    defaultValue,
    references,
    generated,
  ];
}

/// A column under construction, opened by one of [ColumnFactory]'s type
/// methods and refined by whichever modifier applies, in any order, closed
/// by [build].
///
/// [Self] is the builder every modifier hands back, so a chain keeps the
/// modifiers of the type it started with: [TextColumnBuilder.collation] and
/// [IntegerColumnBuilder.autoincrement] stay reachable after any other
/// modifier. [Storage] is the storage class this column holds, and the only one
/// [default_] accepts.
///
/// Unlike Postgres, SQLite has no per-role privilege to guard and no
/// server-side identity sequence to configure, so this stays far smaller
/// than the Postgres builder it mirrors: no `array`, no `identity` options,
/// no geometric or network types.
sealed class ColumnBuilder<Self extends ColumnBuilder<Self, Storage>, Storage extends Value> {
  ColumnBuilder._(this._type);

  final ColumnType _type;
  bool _isPrimary = false;
  bool _isNullable = true;
  bool _unique = false;
  bool _autoincrement = false;
  Collation? _collation;
  ColumnDefault? _default;
  ColumnReference? _references;
  GeneratedColumn? _generated;

  Self get _self => this as Self;

  /// Makes this column the table's primary key, which also refuses a null
  /// value.
  ///
  /// SQLite lets a primary key hold null unless the column says otherwise,
  /// except for an `INTEGER PRIMARY KEY`, where null asks for the next id. A
  /// column that is not an integer is therefore rendered with `NOT NULL` as
  /// well.
  Self isPrimary() {
    _isPrimary = true;
    return _self;
  }

  /// Whether this column accepts a null value. Refuses one when passed
  /// `false`. Accepts one otherwise, including when called with no
  /// argument.
  Self isNullable([bool value = true]) {
    _isNullable = value;
    return _self;
  }

  /// Makes this column refuse a value another row already holds.
  Self unique() {
    _unique = true;
    return _self;
  }

  /// Gives this column [value] when a row does not give it one.
  ///
  /// Accepts only this column's own storage class, so a text column cannot be
  /// handed an [Integer]. Pass the storage class itself, such as `Integer(0)`
  /// or `Varchar('open')`, or a [Value] method that answers one, such
  /// as [Value.boolean]. The `Value.integer` and
  /// `Value.varchar` factories answer a plain [Value] and do
  /// not type-check here.
  ///
  /// Throws an [ArgumentError] for a [Real] that is not finite, since SQL has
  /// no literal for it.
  Self default_(Storage value) {
    if (value case Real(value: final number) when !number.isFinite) {
      throw ArgumentError.value(number, 'value', 'A non-finite REAL has no SQL literal.');
    }
    _default = LiteralDefault(value);
    return _self;
  }

  /// Gives this column the result of a raw SQL expression when a row does
  /// not give it a value, for a default no literal can express, such as the
  /// current time.
  ///
  /// Nothing here validates it, the same choice made for every other raw SQL
  /// fragment a caller supplies.
  Self defaultExpression(String sql) {
    _default = ExpressionDefault(sql);
    return _self;
  }

  /// Makes this column a foreign key, pointing at another table's column.
  Self references(ColumnReference reference) {
    _references = reference;
    return _self;
  }

  /// Makes this column computed from the rest of the row, rather than one a
  /// caller ever writes.
  ///
  /// SQLite refuses this alongside [isPrimary], [default_] or
  /// [defaultExpression] on the same column, and says so when the table is
  /// created. It accepts a [references] that would have to rewrite the
  /// column (`SET NULL`, `SET DEFAULT`, or an update that cascades) and then
  /// fails on the first write that touches the key, so [TableBuilder.columns]
  /// refuses that one.
  Self generated(GeneratedColumn options) {
    _generated = options;
    return _self;
  }

  /// This column's options, exactly as [TableBuilder.columns] reads them
  /// once its own callback returns.
  ColumnDefinition build() => ColumnDefinition._(
    type: _type,
    notNull: _isPrimary || !_isNullable,
    isPrimary: _isPrimary,
    unique: _unique,
    autoincrement: _autoincrement,
    collation: _collation,
    defaultValue: _default,
    references: _references,
    generated: _generated,
  );
}

/// A [ColumnType.integer] column under construction. The only builder that
/// offers `AUTOINCREMENT`, which is legal only on an `INTEGER PRIMARY KEY`.
final class IntegerColumnBuilder extends ColumnBuilder<IntegerColumnBuilder, Integer> {
  IntegerColumnBuilder._() : super._(ColumnType.integer);

  /// Makes this column the table's primary key and makes its rowid grow on
  /// its own, rather than reusing a smaller id a deleted row left behind.
  ///
  /// SQLite allows `AUTOINCREMENT` only on a single-column `INTEGER PRIMARY
  /// KEY` of a table that keeps its rowid, so this sets [isPrimary] itself:
  /// an autoincrement column that is not a primary key cannot be built.
  IntegerColumnBuilder autoincrement() {
    _isPrimary = true;
    _autoincrement = true;
    return this;
  }
}

/// A [ColumnType.real] column under construction.
final class RealColumnBuilder extends ColumnBuilder<RealColumnBuilder, Real> {
  RealColumnBuilder._() : super._(ColumnType.real);
}

/// A [ColumnType.text] column under construction. The only builder that
/// offers a [Collation], since a collating sequence changes how text sorts
/// and compares but says nothing about an integer, a real or a blob.
final class TextColumnBuilder extends ColumnBuilder<TextColumnBuilder, Varchar> {
  TextColumnBuilder._() : super._(ColumnType.text);

  /// Makes this column sort and compare under [collation]. [Collation.binary]
  /// when left out.
  TextColumnBuilder collation(Collation collation) {
    _collation = collation;
    return this;
  }
}

/// A [ColumnType.blob] column under construction.
final class BlobColumnBuilder extends ColumnBuilder<BlobColumnBuilder, Blob> {
  BlobColumnBuilder._() : super._(ColumnType.blob);
}

/// A [ColumnType.any] column under construction, holding whichever storage
/// class a row gives it.
final class AnyColumnBuilder extends ColumnBuilder<AnyColumnBuilder, Value> {
  AnyColumnBuilder._() : super._(ColumnType.any);
}

/// Opens a column of one SQLite type, refined by whichever [ColumnBuilder]
/// modifier [TableBuilder.columns]' own callback chains onto it.
///
/// ```dart
/// TableBuilder('todos').columns((c) => {
///   'id': c.integer().autoincrement(),
///   'title': c.text().isNullable(false).collation(Collation.noCase),
///   'done': c.integer().isNullable(false).default_(Value.boolean(false)),
/// });
/// ```
final class ColumnFactory {
  /// Opens no column on its own; each of its methods does.
  const ColumnFactory();

  /// Opens a [ColumnType.integer] column, capable of [IntegerColumnBuilder.autoincrement].
  IntegerColumnBuilder integer() => IntegerColumnBuilder._();

  /// Opens a [ColumnType.real] column.
  RealColumnBuilder real() => RealColumnBuilder._();

  /// Opens a [ColumnType.text] column, capable of [TextColumnBuilder.collation].
  TextColumnBuilder text() => TextColumnBuilder._();

  /// Opens a [ColumnType.blob] column.
  BlobColumnBuilder blob() => BlobColumnBuilder._();
}

/// What a `STRICT` table offers beyond [ColumnFactory]: the one type only a
/// strict table can hold.
final class StrictColumnFactory extends ColumnFactory {
  /// Opens no column on its own; each of its methods does.
  const StrictColumnFactory._();

  /// Opens an [ColumnType.any] column: a column with no fixed type, which
  /// SQLite accepts only in a `STRICT` table. In an ordinary table it would
  /// have `NUMERIC` affinity and quietly turn the text `'007'` into the
  /// integer `7`, which is why [ColumnFactory] does not offer it.
  AnyColumnBuilder any() => AnyColumnBuilder._();
}

/// What [TableBuilder.columns] takes: a column builder, by the name it holds
/// under, in the order they are declared, which is the order [DeclaredTable]
/// renders them in.
typedef ColumnMap = Map<String, ColumnBuilder<dynamic, Value>>;
