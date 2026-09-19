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

/// Opens one [LocalDatabase.query] (or [DatabaseTransaction.query]) call.
/// Never constructed directly — [LocalDatabase.query] hands one to its own
/// callback. The only method here is [from]: nothing can follow `SELECT`
/// before naming a table, so nothing else is offered here either.
///
/// ```dart
/// final open = await db.query<Todo>(
///   (q) => q.from('todos').where((w) => w.isEqualTo(key: 'done', value: DatabaseType.boolean(false))).map(Todo.fromRow),
/// );
/// ```
final class DatabaseQuery<T extends Object> {
  DatabaseQuery._();

  /// Reads from [name], the same `FROM` a raw `SELECT ... FROM ...` names.
  QueryFrom<T> from(String name) => QueryFrom._(table: _quotedIdentifier(name));
}

/// A [DatabaseQuery] that has named its table, opened by [DatabaseQuery.from].
/// Every method here answers a new [QueryFrom] rather than changing
/// this one, and — unlike [from] itself — every one of them is optional and
/// may be called in any order, since none of them changes what the next one
/// is allowed to be.
final class QueryFrom<T extends Object> {
  const QueryFrom._({
    required String table,
    T Function(DatabaseRow row)? fromRow,
    bool distinct = false,
    List<String>? columns,
    String? where,
    List<DatabaseType>? whereArgs,
    String? groupBy,
    String? having,
    List<DatabaseType>? havingArgs,
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

  final String _table;
  final T Function(DatabaseRow row)? _fromRow;
  final bool _distinct;
  final List<String>? _columns;
  final String? _where;
  final List<DatabaseType>? _whereArgs;
  final String? _groupBy;
  final String? _having;
  final List<DatabaseType>? _havingArgs;
  final String? _orderBy;
  final int? _limit;
  final int? _offset;

  /// Decodes each selected row into a [T] with [fromRow]. Required: nothing
  /// here guesses how a row and a model relate.
  QueryFrom<T> map(T Function(DatabaseRow row) fromRow) => _copyWith(fromRow: fromRow);

  /// Skips a row that duplicates one already read, across the columns
  /// [select] named.
  QueryFrom<T> distinct([bool value = true]) => _copyWith(distinct: value);

  /// Reads only the columns named [columns], instead of every column the
  /// table declares. Called again, it adds columns to the ones already named.
  /// Each name is quoted, so it is read as a column and never
  /// as SQL: an aggregate or an expression belongs in [LocalDatabase.rawQuery].
  QueryFrom<T> select(List<String> columns) =>
      _copyWith(columns: [...?_columns, ...columns.map(_quotedIdentifier)]);

  /// Keeps only the rows [build] matches, composed from an empty
  /// [FilterBuilder]. Called again, it narrows the rows the earlier
  /// call kept: both conditions must hold.
  QueryFrom<T> where(Filter Function(FilterBuilder w) build) {
    final (clause, arguments) = _renderDatabaseFilter(build(const FilterBuilder()));
    return _copyWith(where: _bothMatch(_where, clause), whereArgs: [...?_whereArgs, ...arguments]);
  }

  /// Groups matching rows by the columns named [columns] before [having] and
  /// [map] see them. Called again, it adds columns to the grouping. An empty
  /// list changes nothing. Each name is quoted, so it is read as a column and never
  /// as SQL.
  QueryFrom<T> groupBy(List<String> columns) =>
      columns.isEmpty ? this : _copyWith(groupBy: _appended(_groupBy, columns.map(_quotedIdentifier)));

  /// Keeps only the groups [build] matches, composed from an empty
  /// [FilterBuilder]. Called again, both conditions must hold.
  /// Meaningless without [groupBy].
  ///
  /// A condition over an aggregate goes through [FilterBuilder.raw],
  /// such as `w.raw('COUNT(*) > ?', [DatabaseType.integer(1)])`.
  QueryFrom<T> having(Filter Function(FilterBuilder w) build) {
    final (clause, arguments) = _renderDatabaseFilter(build(const FilterBuilder()));
    return _copyWith(having: _bothMatch(_having, clause), havingArgs: [...?_havingArgs, ...arguments]);
  }

  /// Orders the result by [orders], the first one deciding and each later one
  /// only breaking the ties the one before it left. Called again, its terms
  /// come after the ones already given, so they only break the remaining ties.
  /// An empty list changes nothing.
  QueryFrom<T> orderBy(List<DatabaseOrder> orders) =>
      orders.isEmpty ? this : _copyWith(orderBy: _appended(_orderBy, orders.map(_renderOrder)));

  /// Reads at most [count] rows.
  ///
  /// Throws a [RangeError] if [count] is negative, which SQLite would read as
  /// no limit at all.
  QueryFrom<T> limit(int count) => _copyWith(limit: RangeError.checkNotNegative(count, 'count'));

  /// Skips the first [count] matching rows, applied after [limit].
  ///
  /// Throws a [RangeError] if [count] is negative.
  QueryFrom<T> offset(int count) => _copyWith(offset: RangeError.checkNotNegative(count, 'count'));

  QueryFrom<T> _copyWith({
    T Function(DatabaseRow row)? fromRow,
    bool? distinct,
    List<String>? columns,
    String? where,
    List<DatabaseType>? whereArgs,
    String? groupBy,
    String? having,
    List<DatabaseType>? havingArgs,
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

  List<DatabaseType>? get _arguments =>
      _whereArgs == null && _havingArgs == null ? null : [...?_whereArgs, ...?_havingArgs];

  T Function(DatabaseRow row) get _requiredFromRow =>
      _fromRow ?? (throw StateError('QueryFrom.map was never set.'));
}

/// One term of a query's `ORDER BY`, with the [SortOrder] it sorts in.
///
/// Built through one of two factories, so a column name and a raw SQL
/// expression can never be mistaken for one another: [DatabaseOrder.named]
/// takes a column name and quotes it, [DatabaseOrder.expression] takes SQL and
/// leaves it as written. A `switch` over a [DatabaseOrder] is exhaustive with
/// [NamedOrder] and [ExpressionOrder].
sealed class DatabaseOrder extends Equatable {
  const DatabaseOrder._({required this.order});

  /// The column called [name], sorted in [order].
  const factory DatabaseOrder.named(String name, {SortOrder order}) = NamedOrder._;

  /// The raw SQL [sql], sorted in [order], for a term a bare column cannot
  /// express, such as `lower(title)`.
  ///
  /// Nothing here validates it, the same choice made for every other raw SQL
  /// fragment a caller supplies.
  const factory DatabaseOrder.expression(String sql, {SortOrder order}) = ExpressionOrder._;

  /// The direction this term sorts in.
  final SortOrder order;
}

/// A [DatabaseOrder] that sorts by one column, by name.
final class NamedOrder extends DatabaseOrder {
  const NamedOrder._(this.name, {super.order = SortOrder.asc}) : super._();

  /// The name of the column this term sorts by.
  final String name;

  @override
  List<Object?> get props => [name, order];
}

/// A [DatabaseOrder] that sorts by a raw SQL expression.
final class ExpressionOrder extends DatabaseOrder {
  const ExpressionOrder._(this.sql, {super.order = SortOrder.asc}) : super._();

  /// The SQL expression this term sorts by.
  final String sql;

  @override
  List<Object?> get props => [sql, order];
}

String _appended(String? earlier, Iterable<String> terms) => [?earlier, ...terms].join(', ');

String _renderOrder(DatabaseOrder term) {
  final target = switch (term) {
    NamedOrder(:final name) => _quotedIdentifier(name),
    ExpressionOrder(:final sql) => sql,
  };
  return '$target ${term.order.sql}';
}
