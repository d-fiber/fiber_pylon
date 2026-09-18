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
  DatabaseQueryFrom<T> from(String name) => DatabaseQueryFrom._(table: name);
}

/// A [DatabaseQuery] that has named its table, opened by [DatabaseQuery.from].
/// Every method here answers a new [DatabaseQueryFrom] rather than changing
/// this one, and — unlike [from] itself — every one of them is optional and
/// may be called in any order, since none of them changes what the next one
/// is allowed to be.
final class DatabaseQueryFrom<T extends Object> {
  const DatabaseQueryFrom._({
    required String table,
    T Function(DatabaseRow row)? fromRow,
    bool distinct = false,
    List<String>? columns,
    String? where,
    List<DatabaseType>? whereArgs,
    String? groupBy,
    String? having,
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
  final String? _orderBy;
  final int? _limit;
  final int? _offset;

  /// Decodes each selected row into a [T] with [fromRow]. Required: nothing
  /// here guesses how a row and a model relate.
  DatabaseQueryFrom<T> map(T Function(DatabaseRow row) fromRow) => _copyWith(fromRow: fromRow);

  /// Skips a row that duplicates one already read, across the columns
  /// [select] named.
  DatabaseQueryFrom<T> distinct([bool value = true]) => _copyWith(distinct: value);

  /// Reads only [columns], instead of every column the table declares.
  DatabaseQueryFrom<T> select(List<String> columns) => _copyWith(columns: columns);

  /// Keeps only the rows [build] matches, composed from an empty
  /// [DatabaseFilterBuilder].
  DatabaseQueryFrom<T> where(DatabaseFilter Function(DatabaseFilterBuilder w) build) {
    final (clause, arguments) = _renderDatabaseFilter(build(const DatabaseFilterBuilder()));
    return _copyWith(where: clause, whereArgs: arguments);
  }

  /// Groups matching rows by [clause] before [having] and [map] see them.
  DatabaseQueryFrom<T> groupBy(String clause) => _copyWith(groupBy: clause);

  /// Keeps only the groups [clause] matches. Meaningless without [groupBy].
  DatabaseQueryFrom<T> having(String clause) => _copyWith(having: clause);

  /// Orders the result by [clause].
  DatabaseQueryFrom<T> orderBy(String clause) => _copyWith(orderBy: clause);

  /// Reads at most [count] rows.
  DatabaseQueryFrom<T> limit(int count) => _copyWith(limit: count);

  /// Skips the first [count] matching rows, applied after [limit].
  DatabaseQueryFrom<T> offset(int count) => _copyWith(offset: count);

  DatabaseQueryFrom<T> _copyWith({
    T Function(DatabaseRow row)? fromRow,
    bool? distinct,
    List<String>? columns,
    String? where,
    List<DatabaseType>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => DatabaseQueryFrom._(
    table: _table,
    fromRow: fromRow ?? _fromRow,
    distinct: distinct ?? _distinct,
    columns: columns ?? _columns,
    where: where ?? _where,
    whereArgs: whereArgs ?? _whereArgs,
    groupBy: groupBy ?? _groupBy,
    having: having ?? _having,
    orderBy: orderBy ?? _orderBy,
    limit: limit ?? _limit,
    offset: offset ?? _offset,
  );

  T Function(DatabaseRow row) get _requiredFromRow =>
      _fromRow ?? (throw StateError('DatabaseQueryFrom.map was never set.'));
}
