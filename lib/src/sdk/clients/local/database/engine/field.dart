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

part of 'database.dart';

/// How one Dart type is stored in one column: the storage class the column
/// declares, and the two functions that cross between the Dart value and the
/// [DatabaseType] SQLite holds.
///
/// The columns [DatabaseColumns] opens carry one already. Write one only for a
/// type of your own, and hand it to [DatabaseColumns.custom].
final class DatabaseCodec<V extends Object> {
  /// Codes a [V] through [encode] and [decode], stored as [storage].
  const DatabaseCodec({required this.storage, required this.encode, required this.decode});

  /// The storage class a column of this codec declares.
  final ColumnType storage;

  /// Turns a [V] into the value SQLite stores.
  final DatabaseType Function(V value) encode;

  /// Turns a stored value, never a [Nil], back into a [V].
  final V Function(DatabaseType stored) decode;

  DatabaseCodec<Object> get _erased =>
      DatabaseCodec<Object>(storage: storage, encode: (value) => encode(value as V), decode: decode);
}

class _FieldDefinition {
  const _FieldDefinition({
    required this.codec,
    this.isNullable = false,
    this.isUnique = false,
    this.isPrimary = false,
    this.isAutoincrement = false,
    this.generator,
    this.defaultValue,
    this.reference,
    this.collation,
    this.isolated = false,
    this.referencesIsolated = false,
  });

  final DatabaseCodec<Object> codec;
  final bool isNullable;
  final bool isUnique;
  final bool isPrimary;
  final bool isAutoincrement;
  final DatabaseType Function()? generator;
  final DatabaseType? defaultValue;
  final ColumnReference? reference;
  final Collation? collation;

  /// Whether the table this column belongs to is [Tunnel.isolated].
  final bool isolated;

  /// Whether the column [reference] points at belongs to an isolated table.
  final bool referencesIsolated;

  _FieldDefinition copyWith({
    bool? isNullable,
    bool? isUnique,
    bool? isPrimary,
    DatabaseType? defaultValue,
    ColumnReference? reference,
    Collation? collation,
    bool? referencesIsolated,
  }) => _FieldDefinition(
    codec: codec,
    isNullable: isNullable ?? this.isNullable,
    isUnique: isUnique ?? this.isUnique,
    isPrimary: isPrimary ?? this.isPrimary,
    isAutoincrement: isAutoincrement,
    generator: generator,
    defaultValue: defaultValue ?? this.defaultValue,
    reference: reference ?? this.reference,
    collation: collation ?? this.collation,
    isolated: isolated,
    referencesIsolated: referencesIsolated ?? this.referencesIsolated,
  );

  /// The column this definition declares. An isolated table takes the key, the
  /// uniqueness and the foreign key out of the column itself and states them
  /// on the table instead, where the tenant column can be part of them.
  ColumnBuilder<dynamic, DatabaseType> builder(
    ColumnFactory factory, {
    bool keepPrimary = true,
    bool keepUnique = true,
    bool keepReference = true,
  }) {
    final stored = defaultValue;
    final ColumnBuilder<dynamic, DatabaseType> column = switch ((codec.storage, stored)) {
      (ColumnType.integer, null) => isAutoincrement ? factory.integer().autoincrement() : factory.integer(),
      (ColumnType.integer, final Integer value) => factory.integer().default_(value),
      (ColumnType.real, null) => factory.real(),
      (ColumnType.real, final Real value) => factory.real().default_(value),
      (ColumnType.text, null) => factory.text(),
      (ColumnType.text, final Varchar value) => factory.text().default_(value),
      (ColumnType.blob, null) => factory.blob(),
      (ColumnType.blob, final Blob value) => factory.blob().default_(value),
      (ColumnType.any, _) => throw StateError('A column stored as ANY needs a STRICT table, which a table never is.'),
      _ => throw StateError('The default $stored does not fit the ${codec.storage.name} storage of its column.'),
    };
    column.isNullable(isNullable);
    if (isUnique && keepUnique) column.unique();
    if (isPrimary && keepPrimary) column.isPrimary();
    final target = keepReference ? reference : null;
    if (target != null) column.references(target);
    final ordering = collation;
    if (ordering != null) {
      if (column is! TextColumnBuilder) throw StateError('A collation applies to a text column only.');
      column.collation(ordering);
    }
    return column;
  }
}

/// One column of one declared table, carrying its table, its name, the Dart
/// type [V] it holds and how that type is stored.
///
/// [V] is the Dart type a row gives back, so a column that accepts NULL is a
/// `DatabaseField<Date?>` and one that does not is a `DatabaseField<Date>`.
/// Every filter and every assignment a field builds takes a [V], which is why
/// `todos.done.isEqualTo('yes')` does not compile and `todos.done.isEqualTo(true)`
/// does. Fields are opened by [DatabaseColumns], never constructed directly.
///
/// Two fields are equal when they name the same column of the same table.
base class DatabaseField<V> extends Equatable {
  const DatabaseField._(this.table, this.name, this._definition);

  /// The name of the table this column belongs to.
  final String table;

  /// The name of this column in its table.
  final String name;

  final _FieldDefinition _definition;

  /// Whether this column accepts NULL.
  bool get isNullable => _definition.isNullable;

  /// Whether this column is the whole primary key of its table.
  bool get isPrimary => _definition.isPrimary;

  /// This column, accepting NULL, which a row then gives back as `null`.
  DatabaseField<V?> nullable() => DatabaseField<V?>._(table, name, _definition.copyWith(isNullable: true));

  /// This column, refusing a second row that holds the same value.
  DatabaseField<V> unique() => DatabaseField<V>._(table, name, _definition.copyWith(isUnique: true));

  /// This column as the primary key of its table. The table must then be a
  /// [DatabaseKeyedTable] whose [DatabaseKeyedTable.key] is this column.
  DatabaseField<V> primaryKey() => DatabaseField<V>._(table, name, _definition.copyWith(isPrimary: true));

  /// This column, taking [value] for a row that writes none. A column that
  /// refuses NULL needs one to be added to a table that already holds rows.
  DatabaseField<V> defaultsTo(V value) =>
      DatabaseField<V>._(table, name, _definition.copyWith(defaultValue: _encode(value)));

  /// This column as a foreign key to [target], which must hold the same Dart
  /// type. [onDelete] says what happens to a row here when the row it points
  /// at is deleted, and it refuses the deletion by default.
  DatabaseField<V> references(DatabaseField<V> target, {ReferentialAction onDelete = ReferentialAction.restrict}) =>
      DatabaseField<V>._(
        table,
        name,
        _definition.copyWith(
          reference: ColumnReference(table: target.table, column: target.name, onDelete: onDelete),
          referencesIsolated: target._definition.isolated,
        ),
      );

  /// This column paired with [value], to be written by an insert, an upsert
  /// or an update.
  DatabaseAssignment to(V value) => DatabaseAssignment._(this, _encode(value));

  /// Rows where this column equals [value]. A null [value] on a nullable
  /// column matches the rows holding NULL, which a plain SQL `=` would not.
  DatabaseFilter isEqualTo(V value) => _of(_DatabaseFilterComparison(name, _Comparison.equal, _encode(value)));

  /// Rows where this column differs from [value], the rows holding NULL
  /// included, since a NULL differs from every value.
  DatabaseFilter isNotEqualTo(V value) => _of(_DatabaseFilterComparison(name, _Comparison.notEqual, _encode(value)));

  /// Rows where this column equals one of [values]. A null among them matches
  /// the rows holding NULL. Matches nothing when [values] is empty.
  DatabaseFilter isIn(List<V> values) => _of(_DatabaseFilterIn(name, values.map(_encode).toList()));

  /// Rows where this column equals one of the values [subquery] selects.
  DatabaseFilter isInSelect(DatabaseSubquery<V> subquery) {
    final (clause, arguments) = subquery._render();
    return _of(_DatabaseFilterRaw('${_quotedIdentifier(name)} IN ($clause)', arguments));
  }

  /// Rows where this column holds NULL.
  ///
  /// Throws a [StateError] when this column does not accept NULL, since the
  /// filter could never match.
  DatabaseFilter isNull() {
    _requireNullable('isNull');
    return _of(_DatabaseFilterNull(name, true));
  }

  /// Rows where this column holds a value.
  ///
  /// Throws a [StateError] when this column does not accept NULL, since the
  /// filter would match every row.
  DatabaseFilter isNotNull() {
    _requireNullable('isNotNull');
    return _of(_DatabaseFilterNull(name, false));
  }

  /// The values of this column in the rows [filter] matches, for
  /// [isInSelect]. [filter] must be built from fields of this column's table.
  DatabaseSubquery<V> where(DatabaseFilter filter) => DatabaseSubquery<V>._(this, filter);

  /// This column as a term of an ordering, smallest first.
  DatabaseOrder asc() => DatabaseOrder.expression(_qualified, order: SortOrder.asc);

  /// This column as a term of an ordering, largest first.
  DatabaseOrder desc() => DatabaseOrder.expression(_qualified, order: SortOrder.desc);

  String get _qualified => '${_quotedIdentifier(table)}.${_quotedIdentifier(name)}';

  DatabaseFilter _of(DatabaseFilter filter) => _DatabaseFilterOfTable(filter, table);

  void _requireNullable(String method) {
    if (!isNullable) throw StateError('$method on $this, which does not accept NULL, could never be useful.');
  }

  DatabaseType _encode(V value) => value == null ? const DatabaseType.nil() : _definition.codec.encode(value as Object);

  V _decode(DatabaseType stored) {
    if (stored is Nil) {
      if (_definition.isNullable) return null as V;
      throw StateError('$this is NULL although the column is not declared nullable.');
    }
    return _definition.codec.decode(stored) as V;
  }

  @override
  List<Object?> get props => [table, name];

  @override
  String toString() => '$table.$name';
}

/// A primary key column the engine can fill in: an integer the database
/// numbers itself, or a UUID the engine generates when a record has none yet.
///
/// Opened by [DatabaseColumns.key] and [DatabaseColumns.uuidKey].
final class DatabaseKey<K extends Object> extends DatabaseField<K> {
  const DatabaseKey._(super.table, super.name, super._definition) : super._();

  /// This key paired with [value], or nothing at all when [value] is null, in
  /// which case the engine assigns the key on insert. A record whose key has
  /// not been assigned yet holds a null.
  DatabaseAssignment toOrGenerate(K? value) =>
      value == null ? DatabaseAssignment._(this, null) : DatabaseAssignment._(this, _encode(value));

  DatabaseType? _generate() => _definition.generator?.call();
}

/// A column value paired with the column it is written to, built by
/// [DatabaseField.to]. Only the column that was given it accepts it: the Dart
/// type of the value was checked when it was built.
final class DatabaseAssignment {
  const DatabaseAssignment._(this.field, this._value);

  /// The column this value is written to.
  final DatabaseField<Object?> field;

  final DatabaseType? _value;
}

/// The values of one column in the rows a filter keeps, built by
/// [DatabaseField.where] and consumed by [DatabaseField.isInSelect].
///
/// Its type says which Dart type it selects, so a column can only be matched
/// against a column holding the same type.
final class DatabaseSubquery<V> {
  DatabaseSubquery._(this._field, this._filter) {
    final foreign = _filter._tables.difference({_field.table});
    if (foreign.isNotEmpty) {
      throw ArgumentError.value(
        _filter,
        'filter',
        'This subquery selects ${_field.table}.${_field.name} but its filter reads ${foreign.join(', ')}.',
      );
    }
  }

  final DatabaseField<V> _field;
  final DatabaseFilter _filter;

  (String, List<DatabaseType>) _render() {
    final (clause, arguments) = _renderDatabaseFilter(_filter);
    return ('SELECT ${_field._qualified} FROM ${_quotedIdentifier(_field.table)} WHERE $clause', arguments);
  }
}

/// Ordering filters, available only on a column whose Dart type has an order
/// that matches the order SQLite sorts its stored form in.
///
/// An enum, a UUID, a list and a JSON value have no such order, so those
/// columns offer no `isGreaterThan`. A boolean has none either, since `bool`
/// is not [Comparable]. The argument is never null, even on a nullable column.
extension DatabaseOrderedField<V extends Comparable<Object?>> on DatabaseField<V?> {
  /// Rows where this column is strictly greater than [value]. A row holding
  /// NULL never matches.
  DatabaseFilter isGreaterThan(V value) =>
      _of(_DatabaseFilterComparison(name, _Comparison.greaterThan, _encode(value)));

  /// Rows where this column is greater than [value] or equal to it.
  DatabaseFilter isGreaterThanOrEqualTo(V value) =>
      _of(_DatabaseFilterComparison(name, _Comparison.greaterThanOrEqual, _encode(value)));

  /// Rows where this column is strictly less than [value].
  DatabaseFilter isLessThan(V value) => _of(_DatabaseFilterComparison(name, _Comparison.lessThan, _encode(value)));

  /// Rows where this column is less than [value] or equal to it.
  DatabaseFilter isLessThanOrEqualTo(V value) =>
      _of(_DatabaseFilterComparison(name, _Comparison.lessThanOrEqual, _encode(value)));

  /// Rows where this column lies between [low] and [high], both included.
  DatabaseFilter isBetween(V low, V high) => isGreaterThanOrEqualTo(low) & isLessThanOrEqualTo(high);
}

/// Text filters, available only on a text column. The text is matched as
/// written, `%` and `_` in it standing for themselves, and SQLite ignores the
/// case of ASCII letters.
extension DatabaseTextField<V extends String?> on DatabaseField<V> {
  /// Rows where this column holds [text] somewhere in it.
  DatabaseFilter contains(String text) => _of(_DatabaseFilterLike(name, '%${_escapeLike(text)}%'));

  /// Rows where this column begins with [text].
  DatabaseFilter startsWith(String text) => _of(_DatabaseFilterLike(name, '${_escapeLike(text)}%'));

  /// Rows where this column ends with [text].
  DatabaseFilter endsWith(String text) => _of(_DatabaseFilterLike(name, '%${_escapeLike(text)}'));

  /// This column, comparing and sorting text under [collation]. With
  /// [Collation.noCase], `Ada` and `ADA` are one value, unique columns
  /// included.
  DatabaseField<V> collatedBy(Collation collation) =>
      DatabaseField<V>._(table, name, _definition.copyWith(collation: collation));
}
