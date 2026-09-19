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

/// The type a column declares, spelled as a `STRICT` table of SQLite takes it.
///
/// SQLite enforces the type only in a `STRICT` table. In any other it is a hint
/// that a value may not follow.
enum ColumnType {
  /// A signed integer, up to 64 bits.
  integer,

  /// A floating point value.
  real,

  /// Text.
  text,

  /// Raw bytes.
  blob,

  /// Any storage class at all, kept exactly as written, for a column with no
  /// fixed type.
  ///
  /// Only [StrictColumnFactory.any] offers it. Outside a `STRICT` table SQLite
  /// gives the keyword `ANY` numeric affinity and rewrites the text `'007'` into
  /// the integer `7`.
  any,
}

/// A collating sequence SQLite ships with, which decides how a text column
/// sorts and compares.
///
/// SQLite through sqflite offers no way to register another one, so these are
/// the only ones a column can use.
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

/// What a foreign key does to a referencing row when the row it points at is
/// deleted or has its key changed.
enum ReferentialAction {
  /// Does nothing of its own, the same as leaving the action out.
  noAction,

  /// Refuses the change that would strand the referencing row.
  restrict,

  /// Carries the change through to the referencing row.
  cascade,

  /// Sets the referencing column to null, so the column must accept null.
  setNull,

  /// Sets the referencing column to its declared default, so the column needs
  /// one.
  setDefault,
}

/// The moment a deferrable foreign key is checked.
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

/// How a [GeneratedColumn] keeps its value.
enum GeneratedStorage {
  /// Computed once, when the row is written, and kept in the database file.
  stored,

  /// Recomputed on every read, so it takes no room in the database file.
  virtual,
}

/// What a column takes when a row gives it no value, either a fixed [Value]
/// ([LiteralDefault]) or a raw SQL expression ([ExpressionDefault]).
sealed class ColumnDefault extends Equatable {
  const ColumnDefault();
}

/// A default that is one fixed value.
///
/// The caller passes the [Value] itself, and quoting a [Varchar] or spelling a
/// [Blob] in hexadecimal is left to the table declaration.
final class LiteralDefault extends ColumnDefault {
  /// Creates a default of [value].
  const LiteralDefault(this.value);

  /// The value a row takes when it gives none.
  final Value value;

  @override
  List<Object?> get props => [value];
}

/// A default computed by a raw SQL expression.
///
/// Nothing here validates it, the same choice made for every other raw SQL
/// fragment a caller supplies. [DeclaredTable.addColumnStatement] refuses a
/// column with such a default.
final class ExpressionDefault extends ColumnDefault {
  /// Creates a default computed by [sql].
  const ExpressionDefault(this.sql);

  /// The SQL expression evaluated for each row that gives no value.
  final String sql;

  @override
  List<Object?> get props => [sql];
}

/// A foreign key from a column to a column of another table.
///
/// Left off [column], the reference points at the primary key of [table].
final class ColumnReference extends Equatable {
  /// Creates a reference to [table], and to its [column] when given one.
  const ColumnReference({required this.table, this.column, this.onDelete, this.onUpdate, this.deferral});

  /// The table this column points at.
  final String table;

  /// The column of [table] this column points at. Its primary key when left
  /// out.
  final String? column;

  /// What happens to the referencing row when the referenced row is deleted.
  /// [ReferentialAction.noAction] when left out.
  final ReferentialAction? onDelete;

  /// What happens to the referencing row when the referenced row's key changes.
  /// [ReferentialAction.noAction] when left out.
  final ReferentialAction? onUpdate;

  /// When this constraint is checked, if it may be checked later than the
  /// statement that broke it. The constraint is not deferrable when left out.
  final Deferral? deferral;

  @override
  List<Object?> get props => [table, column, onDelete, onUpdate, deferral];
}

/// How SQLite computes a column from the rest of its row, for a column a caller
/// never writes.
final class GeneratedColumn extends Equatable {
  /// Creates the definition of a column computed by [expression] and kept as
  /// [storage] says.
  const GeneratedColumn({required this.expression, required this.storage});

  /// The SQL expression that computes the column, in terms of the other
  /// columns of the table.
  ///
  /// Nothing here validates it, the same choice [ColumnBuilder.defaultExpression]
  /// makes for raw SQL no closed vocabulary covers.
  final String expression;

  /// Whether the value is kept in the database file or recomputed on every
  /// read.
  final GeneratedStorage storage;

  @override
  List<Object?> get props => [expression, storage];
}

/// A column as a [ColumnBuilder] resolved it, ready for a [DeclaredTable] to
/// create.
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

  /// Whether this column refuses a null value, which a primary key column
  /// always does.
  final bool notNull;

  /// Whether this column is the table's single-column primary key.
  ///
  /// A composite primary key is held by [DeclaredTable.primaryKey] instead.
  final bool isPrimary;

  /// Whether this column refuses a value another row already holds.
  final bool unique;

  /// Whether the id of this column keeps growing rather than reusing the id of
  /// a deleted row. Only true together with [isPrimary].
  final bool autoincrement;

  /// The collating sequence this column sorts and compares under. Null when
  /// left out, and SQLite then uses [Collation.binary].
  final Collation? collation;

  /// What this column takes when a row does not give it a value. Null when
  /// it takes none.
  final ColumnDefault? defaultValue;

  /// The foreign key this column carries. Null when it carries none.
  final ColumnReference? references;

  /// How this column's value is computed from the rest of the row. Null when
  /// it is an ordinary column.
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

/// A column under construction, started by one of the type methods of
/// [ColumnFactory] and refined by whichever modifier applies, in any order.
///
/// [Self] is the builder every modifier hands back, so a chain keeps the
/// modifiers of the type it started with: [TextColumnBuilder.collation] and
/// [IntegerColumnBuilder.autoincrement] stay reachable after any other
/// modifier. [Storage] is the storage class this column holds, and the only one
/// [default_] accepts.
sealed class ColumnBuilder<Self extends ColumnBuilder<Self, Storage>, Storage extends Value> {
  ColumnBuilder._(this._type);

  /// Backs [ColumnDefinition.type].
  final ColumnType _type;

  /// Backs [ColumnDefinition.isPrimary].
  bool _isPrimary = false;

  /// Whether this column accepts null, which [ColumnDefinition.notNull] negates.
  bool _isNullable = true;

  /// Backs [ColumnDefinition.unique].
  bool _unique = false;

  /// Backs [ColumnDefinition.autoincrement].
  bool _autoincrement = false;

  /// Backs [ColumnDefinition.collation].
  Collation? _collation;

  /// Backs [ColumnDefinition.defaultValue].
  ColumnDefault? _default;

  /// Backs [ColumnDefinition.references].
  ColumnReference? _references;

  /// Backs [ColumnDefinition.generated].
  GeneratedColumn? _generated;

  Self get _self => this as Self;

  /// Makes this column the table's primary key, which also refuses a null
  /// value.
  ///
  /// SQLite alone would let a primary key hold null, except in an `INTEGER
  /// PRIMARY KEY`, where null asks for the next id. This column refuses null
  /// whatever its type.
  ///
  /// [TableBuilderBase.columns] throws an [ArgumentError] when the table also
  /// declares a composite [TableBuilderBase.primaryKey].
  Self isPrimary() {
    _isPrimary = true;
    return _self;
  }

  /// Sets whether this column accepts a null value.
  ///
  /// A column accepts null unless this is called with `false`.
  Self isNullable([bool value = true]) {
    _isNullable = value;
    return _self;
  }

  /// Makes this column refuse a value another row already holds.
  ///
  /// SQLite still lets several rows hold null.
  Self unique() {
    _unique = true;
    return _self;
  }

  /// Gives this column [value] when a row does not give it one.
  ///
  /// Accepts only this column's own storage class, so a text column cannot be
  /// handed an [Integer]. Pass the storage class itself, such as `Integer(0)`
  /// or `Varchar('open')`, or a [Value] method that answers one, such as
  /// [Value.boolean]. The `Value.integer` and `Value.varchar` factories answer
  /// a plain [Value] and do not type-check here.
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
  /// fragment a caller supplies. [DeclaredTable.addColumnStatement] refuses a
  /// column with such a default.
  Self defaultExpression(String sql) {
    _default = ExpressionDefault(sql);
    return _self;
  }

  /// Makes this column a foreign key that follows [reference].
  Self references(ColumnReference reference) {
    _references = reference;
    return _self;
  }

  /// Makes this column computed from the rest of the row as [options] says,
  /// rather than one a caller ever writes.
  ///
  /// SQLite refuses this alongside [isPrimary], [default_] or
  /// [defaultExpression] on the same column, and says so when the table is
  /// created. It accepts a [references] that would have to rewrite the
  /// column (`SET NULL`, `SET DEFAULT`, or an update that cascades) and then
  /// fails on the first write that touches the key, so
  /// [TableBuilderBase.columns] throws an [ArgumentError] for that one.
  Self generated(GeneratedColumn options) {
    _generated = options;
    return _self;
  }

  /// The [ColumnDefinition] this builder has resolved.
  ///
  /// [TableBuilderBase.columns] calls it once its callback returns, so a caller
  /// rarely needs to.
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

/// A [ColumnType.integer] column under construction, the only builder that
/// offers `AUTOINCREMENT`.
final class IntegerColumnBuilder extends ColumnBuilder<IntegerColumnBuilder, Integer> {
  IntegerColumnBuilder._() : super._(ColumnType.integer);

  /// Makes this column the table's primary key, and makes its id keep growing
  /// rather than reuse a smaller id a deleted row left behind.
  ///
  /// SQLite allows `AUTOINCREMENT` only on the single-column `INTEGER PRIMARY
  /// KEY` of a table that keeps its rowid, so this calls [isPrimary] itself,
  /// and SQLite refuses it in a table declared [TableBuilderBase.withoutRowid]
  /// when the table is created.
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

/// A [ColumnType.text] column under construction, the only builder that offers
/// a [Collation], since a collating sequence only means something for text.
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

/// The starting point of a column, handed to the callback of
/// [TableBuilderBase.columns].
///
/// ```dart
/// TableBuilder('todos').columns((c) => {
///   'id': c.integer().autoincrement(),
///   'title': c.text().isNullable(false).collation(Collation.noCase),
///   'done': c.integer().isNullable(false).default_(Value.boolean(false)),
/// });
/// ```
final class ColumnFactory {
  /// Creates a factory, which [TableBuilderBase.columns] already supplies to its
  /// callback.
  const ColumnFactory();

  /// Starts a [ColumnType.integer] column, the only kind that can be
  /// [IntegerColumnBuilder.autoincrement].
  IntegerColumnBuilder integer() => IntegerColumnBuilder._();

  /// Starts a [ColumnType.real] column.
  RealColumnBuilder real() => RealColumnBuilder._();

  /// Starts a [ColumnType.text] column, the only kind that takes a [TextColumnBuilder.collation].
  TextColumnBuilder text() => TextColumnBuilder._();

  /// Starts a [ColumnType.blob] column.
  BlobColumnBuilder blob() => BlobColumnBuilder._();
}

/// The starting point of a column in a `STRICT` table, which offers [any] on top
/// of what [ColumnFactory] does.
final class StrictColumnFactory extends ColumnFactory {
  const StrictColumnFactory._();

  /// Starts a [ColumnType.any] column, with no fixed type.
  ///
  /// Only a `STRICT` table offers it. In an ordinary table such a column would
  /// have `NUMERIC` affinity and quietly turn the text `'007'` into the integer
  /// `7`.
  AnyColumnBuilder any() => AnyColumnBuilder._();
}

/// The columns of a table, by name, in the order [DeclaredTable] creates them.
typedef ColumnMap = Map<String, ColumnBuilder<dynamic, Value>>;
