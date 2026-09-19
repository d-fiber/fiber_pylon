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

part of '../database.dart';

/// How values of the Dart type [V] are stored in a column.
///
/// The columns [Columns] opens carry one already. Write one only for a type of
/// your own, and hand it to [Columns.custom].
final class ColumnCodec<V extends Object> {
  /// Creates a codec that stores a [V] as [storage], written by [encode] and
  /// read back by [decode].
  const ColumnCodec({required this.storage, required this.encode, required this.decode});

  /// The storage class of a column that uses this codec.
  final ColumnType storage;

  /// The function that turns a [V] into the value to store.
  final Value Function(V value) encode;

  /// The function that turns a stored value back into a [V].
  ///
  /// It is never called with a [Nil]: a NULL is read as `null` before the codec
  /// is asked, or is an error on a column that does not accept NULL.
  final V Function(Value stored) decode;

  ColumnCodec<Object> get _erased =>
      ColumnCodec<Object>(storage: storage, encode: (value) => encode(value as V), decode: decode);
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

  final ColumnCodec<Object> codec;
  final bool isNullable;
  final bool isUnique;
  final bool isPrimary;
  final bool isAutoincrement;
  final Value Function()? generator;
  final Value? defaultValue;
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
    Value? defaultValue,
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

  /// The column this definition declares, without its primary key, its
  /// uniqueness or its foreign key when [keepPrimary], [keepUnique] or
  /// [keepReference] is false.
  ///
  /// An isolated table turns them off and states them on the table instead,
  /// where the tenant column can be part of them.
  ColumnBuilder<dynamic, Value> builder(
    ColumnFactory factory, {
    bool keepPrimary = true,
    bool keepUnique = true,
    bool keepReference = true,
  }) {
    final stored = defaultValue;
    final ColumnBuilder<dynamic, Value> column = switch ((codec.storage, stored)) {
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

/// One column of one declared table, holding values of the Dart type [V].
///
/// [V] is the type a row gives back, so a column that accepts NULL is a
/// `Field<Date?>` and one that does not is a `Field<Date>`. Every filter and
/// every assignment a field builds takes a [V], which is why
/// `todos.done.isEqualTo('yes')` does not compile and `todos.done.isEqualTo(true)`
/// does.
///
/// Fields are opened by [Columns], never constructed directly. Two fields are
/// equal when they name the same column of the same table.
base class Field<V> extends Equatable {
  const Field._(this.table, this.name, this._definition);

  /// The name of the table this column belongs to.
  final String table;

  /// The name of this column in its table.
  final String name;

  /// How this column is declared: its storage, its constraints and its default.
  final _FieldDefinition _definition;

  /// Whether this column accepts NULL.
  bool get isNullable => _definition.isNullable;

  /// Whether this column is the whole primary key of its table.
  bool get isPrimary => _definition.isPrimary;

  /// This column, accepting NULL, which a row then gives back as `null`.
  Field<V?> nullable() => Field<V?>._(table, name, _definition.copyWith(isNullable: true));

  /// This column, refusing a second row that holds the same value.
  ///
  /// On an isolated table the check is made within one tenant's rows.
  Field<V> unique() => Field<V>._(table, name, _definition.copyWith(isUnique: true));

  /// This column as the primary key of its table.
  ///
  /// A [KeyedTable] needs exactly one such column, which is then its
  /// [KeyedTable.keyField].
  Field<V> primaryKey() => Field<V>._(table, name, _definition.copyWith(isPrimary: true));

  /// This column, taking [value] for a row that writes none.
  ///
  /// A column that refuses NULL needs one to be added to a table that already
  /// holds rows.
  Field<V> defaultsTo(V value) => Field<V>._(table, name, _definition.copyWith(defaultValue: _encode(value)));

  /// This column as a foreign key to [target], which must hold the same Dart
  /// type.
  ///
  /// [onDelete] says what happens to a row here when the row it points at is
  /// deleted. By default the deletion is refused.
  Field<V> references(Field<V> target, {ReferentialAction onDelete = ReferentialAction.restrict}) => Field<V>._(
    table,
    name,
    _definition.copyWith(
      reference: ColumnReference(table: target.table, column: target.name, onDelete: onDelete),
      referencesIsolated: target._definition.isolated,
    ),
  );

  /// This column paired with [value], to be written by an insert, an upsert or
  /// an update.
  Assignment to(V value) => Assignment._(this, _encode(value));

  /// Rows where this column equals [value].
  ///
  /// A null [value] on a nullable column matches the rows holding NULL, which a
  /// plain SQL `=` would not.
  Filter isEqualTo(V value) => _of(_FilterComparison(name, _Comparison.equal, _encode(value)));

  /// Rows where this column differs from [value], the rows holding NULL
  /// included, since a NULL differs from every value.
  ///
  /// A null [value] on a nullable column matches the rows holding a value.
  Filter isNotEqualTo(V value) => _of(_FilterComparison(name, _Comparison.notEqual, _encode(value)));

  /// Rows where this column equals one of [values].
  ///
  /// A null among them matches the rows holding NULL. Nothing matches when
  /// [values] is empty.
  Filter isIn(List<V> values) => _of(_FilterIn(name, values.map(_encode).toList()));

  /// Rows where this column equals one of the values [subquery] selects.
  Filter isInSelect(Subquery<V> subquery) {
    final (clause, arguments) = subquery._render();
    return _of(_FilterRaw('${_quotedIdentifier(name)} IN ($clause)', arguments));
  }

  /// Rows where this column holds NULL.
  ///
  /// Throws a [StateError] when this column does not accept NULL, since the
  /// filter could never match.
  Filter isNull() {
    _requireNullable('isNull');
    return _of(_FilterNull(name, true));
  }

  /// Rows where this column holds a value.
  ///
  /// Throws a [StateError] when this column does not accept NULL, since the
  /// filter would match every row.
  Filter isNotNull() {
    _requireNullable('isNotNull');
    return _of(_FilterNull(name, false));
  }

  /// The values of this column in the rows [filter] matches, for [isInSelect].
  ///
  /// Throws an [ArgumentError] when [filter] reads another table than this
  /// column's.
  Subquery<V> where(Filter filter) => Subquery<V>._(this, filter);

  /// This column as a term of an ordering, smallest first.
  Sort asc() => Sort.expression(_qualified, order: SortOrder.asc);

  /// This column as a term of an ordering, largest first.
  Sort desc() => Sort.expression(_qualified, order: SortOrder.desc);

  String get _qualified => '${_quotedIdentifier(table)}.${_quotedIdentifier(name)}';

  Filter _of(Filter filter) => _FilterOfTable(filter, table);

  void _requireNullable(String method) {
    if (!isNullable) throw StateError('$method on $this, which does not accept NULL, could never be useful.');
  }

  Value _encode(V value) => value == null ? const Value.nil() : _definition.codec.encode(value as Object);

  V _decode(Value stored) {
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
/// Opened by [Columns.key] and [Columns.uuidKey].
final class KeyField<K extends Object> extends Field<K> {
  const KeyField._(super.table, super.name, super._definition) : super._();

  /// This key paired with [value], or with nothing when [value] is null, in
  /// which case an insert lets the engine assign the key.
  ///
  /// It is meant for a record whose key is null until it is first saved. An
  /// update leaves the key as it is when [value] is null.
  Assignment toOrGenerate(K? value) => value == null ? Assignment._(this, null) : Assignment._(this, _encode(value));

  Value? _generate() => _definition.generator?.call();
}

/// The terms of an ordering, added one after the other by the callback given to
/// [Rows.orderBy].
///
/// ```dart
/// db.from(users).orderBy((o) => o.asc(users.city).desc(users.age)).stream();
/// ```
///
/// Each term is a column of a table, so an ordering by a name that does not
/// exist does not compile.
final class OrderBuilder {
  OrderBuilder._();

  final List<Sort> _terms = [];

  /// Orders by [field], smallest first, after the terms already added.
  OrderBuilder asc(Field<Object?> field) {
    _terms.add(field.asc());
    return this;
  }

  /// Orders by [field], largest first, after the terms already added.
  OrderBuilder desc(Field<Object?> field) {
    _terms.add(field.desc());
    return this;
  }
}

/// A value paired with the column it is written to, built by [Field.to].
///
/// The Dart type of the value was checked against the column when it was built,
/// so no other column accepts it.
final class Assignment {
  const Assignment._(this.field, this._value) : _isIncrement = false;

  const Assignment._increment(this.field, Value this._value) : _isIncrement = true;

  /// The column this value is written to.
  final Field<Object?> field;

  /// The value to write, or `null` when the engine decides.
  final Value? _value;

  /// Whether [_value] is an amount to add to what the column holds, rather than
  /// what the column becomes.
  final bool _isIncrement;
}

/// Arithmetic on a numeric column, available only on a column whose Dart type
/// is a number.
extension NumericField<V extends num> on Field<V?> {
  /// This column paired with [amount] to add to what it holds, to be written by
  /// an update.
  ///
  /// A NULL counts as zero, and a negative [amount] subtracts. The addition is
  /// made by the database, not read and written back, so two updates at once
  /// never lose one of the two. An insert and an upsert throw a [StateError]
  /// when given it, since a new row has nothing to add to.
  Assignment incrementBy(V amount) => Assignment._increment(this, _encode(amount));
}

/// The values of one column in the rows a filter keeps, built by
/// [Field.where] and consumed by [Field.isInSelect].
///
/// Its type says which Dart type it selects, so a column can only be matched
/// against a column holding the same type.
final class Subquery<V> {
  Subquery._(this._field, this._filter) {
    final foreign = _filter._tables.difference({_field.table});
    if (foreign.isNotEmpty) {
      throw ArgumentError.value(
        _filter,
        'filter',
        'This subquery selects ${_field.table}.${_field.name} but its filter reads ${foreign.join(', ')}.',
      );
    }
  }

  /// The column whose values are selected.
  final Field<V> _field;

  /// The filter that keeps the rows.
  final Filter _filter;

  (String, List<Value>) _render() {
    final (clause, arguments) = _renderDatabaseFilter(_filter);
    return ('SELECT ${_field._qualified} FROM ${_quotedIdentifier(_field.table)} WHERE $clause', arguments);
  }
}

/// Ordering filters, available only on a column whose Dart type is [Comparable]
/// and orders the way its stored form does.
///
/// An enum, a UUID, a list and a JSON value have no such order, so those
/// columns offer none of these filters. A boolean has none either, since `bool`
/// is not [Comparable]. The argument is never null, even on a nullable column.
extension OrderedField<V extends Comparable<Object?>> on Field<V?> {
  /// Rows where this column is strictly greater than [value]. A row holding
  /// NULL never matches.
  Filter isGreaterThan(V value) => _of(_FilterComparison(name, _Comparison.greaterThan, _encode(value)));

  /// Rows where this column is greater than [value] or equal to it.
  Filter isGreaterThanOrEqualTo(V value) =>
      _of(_FilterComparison(name, _Comparison.greaterThanOrEqual, _encode(value)));

  /// Rows where this column is strictly less than [value].
  Filter isLessThan(V value) => _of(_FilterComparison(name, _Comparison.lessThan, _encode(value)));

  /// Rows where this column is less than [value] or equal to it.
  Filter isLessThanOrEqualTo(V value) => _of(_FilterComparison(name, _Comparison.lessThanOrEqual, _encode(value)));

  /// Rows where this column lies between [low] and [high], both included.
  Filter isBetween(V low, V high) => isGreaterThanOrEqualTo(low) & isLessThanOrEqualTo(high);
}

/// Text filters, available only on a text column.
///
/// The text is matched as written, `%` and `_` in it standing for themselves,
/// and the case of ASCII letters is ignored.
extension StringField<V extends String?> on Field<V> {
  /// Rows where this column holds [text] somewhere in it.
  Filter contains(String text) => _of(_FilterLike(name, '%${_escapeLike(text)}%'));

  /// Rows where this column begins with [text].
  Filter startsWith(String text) => _of(_FilterLike(name, '${_escapeLike(text)}%'));

  /// Rows where this column ends with [text].
  Filter endsWith(String text) => _of(_FilterLike(name, '%${_escapeLike(text)}'));

  /// This column, comparing and sorting text under [collation].
  ///
  /// With [Collation.noCase], `Ada` and `ADA` are one value, unique columns
  /// included.
  Field<V> collatedBy(Collation collation) => Field<V>._(table, name, _definition.copyWith(collation: collation));
}
