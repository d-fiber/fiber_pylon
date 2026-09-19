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

/// A query that has not yet named its table.
///
/// [LocalDatabase.query], [TransactionScope.query] and [StatementBatch.query]
/// hand one to their callback, which names the table with [from] and returns
/// the result. [T] is the type each row is decoded into.
///
/// ```dart
/// final open = await LocalDatabase.query<Todo>(
///   (q) => q.from('todos').where((w) => w.isEqualTo(key: 'done', value: Value.boolean(false))).map(Todo.fromRow),
/// );
/// ```
final class Select<T extends Object> {
  Select._();

  /// Reads from the table called [name].
  QueryFrom<T> from(String name) => QueryFrom._(table: _quotedIdentifier(name));
}

/// A query that has named its table, and is complete as it stands.
///
/// Without any further call it reads every column of every row. Each method
/// answers a new [QueryFrom] and leaves this one unchanged, and they may be
/// called in any order.
final class QueryFrom<T extends Object> {
  const QueryFrom._({
    required String table,
    T Function(RawRow row)? fromRow,
    bool distinct = false,
    List<String>? columns,
    String? where,
    List<Value>? whereArgs,
    String? groupBy,
    String? having,
    List<Value>? havingArgs,
    String? orderBy,
    int? limit,
    int? offset,
  }) : _table = table,
       _fromRow = fromRow,
       _distinct = distinct,
       _columns = columns,
       _where = where,
       _whereArgs = whereArgs,
       _groupBy = groupBy,
       _having = having,
       _havingArgs = havingArgs,
       _orderBy = orderBy,
       _limit = limit,
       _offset = offset;

  /// The name of the table to read from.
  final String _table;

  /// Decodes a row into a [T], or `null` until [map] is called.
  final T Function(RawRow row)? _fromRow;

  /// Whether a row that repeats one already read is skipped.
  final bool _distinct;

  /// The columns to read, or `null` for every column.
  final List<String>? _columns;

  /// The condition a row must meet to be read, or `null` for every row.
  final String? _where;

  /// The values bound to the placeholders of [_where].
  final List<Value>? _whereArgs;

  /// The columns rows are grouped by, or `null` for no grouping.
  final String? _groupBy;

  /// The condition a group must meet to be read, or `null` for every group.
  final String? _having;

  /// The values bound to the placeholders of [_having].
  final List<Value>? _havingArgs;

  /// The terms rows are ordered by, or `null` for no promised order.
  final String? _orderBy;

  /// The most rows to read, or `null` for no limit.
  final int? _limit;

  /// The number of matching rows to skip, or `null` to skip none.
  final int? _offset;

  /// Decodes each selected row into a [T] with [fromRow].
  ///
  /// [LocalDatabase.query] and [TransactionScope.query] throw a [StateError]
  /// when the query runs without it. A [StatementBatch.query] does not read it,
  /// since its rows come back undecoded.
  QueryFrom<T> map(T Function(RawRow row) fromRow) => _copyWith(fromRow: fromRow);

  /// Skips a row that repeats one already read, comparing the columns [select]
  /// named, or every column when it was not called.
  ///
  /// Pass `false` to read repeated rows again.
  QueryFrom<T> distinct([bool value = true]) => _copyWith(distinct: value);

  /// Reads only the columns called [columns], instead of every column.
  ///
  /// Called again, it adds columns to the ones already named. Each name is read
  /// as a column, never as SQL, so an aggregate or an expression belongs in
  /// [LocalDatabase.rawQuery].
  QueryFrom<T> select(List<String> columns) => _copyWith(columns: [...?_columns, ...columns.map(_quotedIdentifier)]);

  /// Reads only the rows [build] matches.
  ///
  /// [build] receives an empty [FilterBuilder]. Called again, a row must meet
  /// both conditions to be read.
  QueryFrom<T> where(Filter Function(FilterBuilder w) build) {
    final (clause, arguments) = _renderDatabaseFilter(build(const FilterBuilder()));
    return _copyWith(where: _bothMatch(_where, clause), whereArgs: [...?_whereArgs, ...arguments]);
  }

  /// Groups the matching rows by the columns called [columns].
  ///
  /// Called again, it adds columns to the grouping. An empty list changes
  /// nothing. Each name is read as a column, never as SQL.
  QueryFrom<T> groupBy(List<String> columns) =>
      columns.isEmpty ? this : _copyWith(groupBy: _appended(_groupBy, columns.map(_quotedIdentifier)));

  /// Reads only the groups [build] matches.
  ///
  /// [build] receives an empty [FilterBuilder]. Called again, a group must meet
  /// both conditions to be read. A condition over an aggregate goes through
  /// [FilterBuilder.raw], such as `w.raw('COUNT(*) > ?', [Value.integer(1)])`.
  ///
  /// Needs [groupBy]: a query that has this without it throws an
  /// [ArgumentError] when it runs or is queued in a [StatementBatch].
  QueryFrom<T> having(Filter Function(FilterBuilder w) build) {
    final (clause, arguments) = _renderDatabaseFilter(build(const FilterBuilder()));
    return _copyWith(having: _bothMatch(_having, clause), havingArgs: [...?_havingArgs, ...arguments]);
  }

  /// Orders the rows by [orders], the first deciding and each later one only
  /// breaking the ties the one before it left.
  ///
  /// Called again, its terms come after the ones already given. An empty list
  /// changes nothing.
  QueryFrom<T> orderBy(List<Sort> orders) =>
      orders.isEmpty ? this : _copyWith(orderBy: _appended(_orderBy, orders.map(_renderOrder)));

  /// Reads at most [count] rows.
  ///
  /// Throws a [RangeError] if [count] is negative, which SQLite would read as
  /// no limit at all.
  QueryFrom<T> limit(int count) => _copyWith(limit: RangeError.checkNotNegative(count, 'count'));

  /// Skips the first [count] matching rows, before [limit] counts the ones to
  /// read.
  ///
  /// Works without [limit]. Throws a [RangeError] if [count] is negative.
  QueryFrom<T> offset(int count) => _copyWith(offset: RangeError.checkNotNegative(count, 'count'));

  QueryFrom<T> _copyWith({
    T Function(RawRow row)? fromRow,
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Value>? whereArgs,
    String? groupBy,
    String? having,
    List<Value>? havingArgs,
    String? orderBy,
    int? limit,
    int? offset,
  }) => QueryFrom._(
    table: _table,
    fromRow: fromRow ?? _fromRow,
    distinct: distinct ?? _distinct,
    columns: columns ?? _columns,
    where: where ?? _where,
    whereArgs: whereArgs ?? _whereArgs,
    groupBy: groupBy ?? _groupBy,
    having: having ?? _having,
    havingArgs: havingArgs ?? _havingArgs,
    orderBy: orderBy ?? _orderBy,
    limit: limit ?? _limit,
    offset: offset ?? _offset,
  );

  List<Value>? get _arguments => _whereArgs == null && _havingArgs == null ? null : [...?_whereArgs, ...?_havingArgs];

  T Function(RawRow row) get _requiredFromRow => _fromRow ?? (throw StateError('QueryFrom.map was never set.'));
}

/// One term of a query's `ORDER BY`, with the [SortOrder] it sorts in.
///
/// Built by one of two factories, so that a column name is never mistaken for
/// SQL: [Sort.named] takes a column name and [Sort.expression] takes SQL. A
/// `switch` over a [Sort] is exhaustive with [NamedSort] and [ExpressionSort].
sealed class Sort extends Equatable {
  const Sort._({required this.order});

  /// A term that sorts by the column called [name] in [order].
  const factory Sort.named(String name, {SortOrder order}) = NamedSort._;

  /// A term that sorts by the SQL expression [sql] in [order], for what a bare
  /// column cannot express, such as `lower(title)`.
  ///
  /// [sql] is not validated, as with every raw SQL fragment this package takes.
  const factory Sort.expression(String sql, {SortOrder order}) = ExpressionSort._;

  /// The direction this term sorts in.
  final SortOrder order;
}

/// A term of an `ORDER BY` that sorts by one column, by name.
final class NamedSort extends Sort {
  const NamedSort._(this.name, {super.order = SortOrder.asc}) : super._();

  /// The name of the column this term sorts by.
  final String name;

  @override
  List<Object?> get props => [name, order];
}

/// A term of an `ORDER BY` that sorts by a SQL expression.
final class ExpressionSort extends Sort {
  const ExpressionSort._(this.sql, {super.order = SortOrder.asc}) : super._();

  /// The SQL expression this term sorts by.
  final String sql;

  @override
  List<Object?> get props => [sql, order];
}

String _appended(String? earlier, Iterable<String> terms) => [?earlier, ...terms].join(', ');

String _renderOrder(Sort term) {
  final target = switch (term) {
    NamedSort(:final name) => _quotedIdentifier(name),
    ExpressionSort(:final sql) => sql,
  };
  return '$target ${term.order.sql}';
}
