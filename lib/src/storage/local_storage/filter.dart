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

/// One condition a `WHERE` clause can hold, built through
/// [DatabaseFilterBuilder] rather than written as a raw SQL string. Never
/// implemented outside this file: [DatabaseQueryFrom.where],
/// [DatabaseUpdateSet.where] and [DatabaseDeleteFrom.where] each read one
/// back into the raw `WHERE` clause and bound arguments sqflite itself
/// takes.
sealed class DatabaseFilter {
  const DatabaseFilter();
}

final class _DatabaseFilterComparison extends DatabaseFilter {
  const _DatabaseFilterComparison(this.column, this.operator, this.value);

  final String column;
  final String operator;
  final DatabaseType value;
}

final class _DatabaseFilterIn extends DatabaseFilter {
  const _DatabaseFilterIn(this.column, this.values);

  final String column;
  final List<DatabaseType> values;
}

final class _DatabaseFilterNull extends DatabaseFilter {
  const _DatabaseFilterNull(this.column, this.isNull);

  final String column;
  final bool isNull;
}

final class _DatabaseFilterNot extends DatabaseFilter {
  const _DatabaseFilterNot(this.filter);

  final DatabaseFilter filter;
}

final class _DatabaseFilterCombination extends DatabaseFilter {
  const _DatabaseFilterCombination(this.connector, this.filters);

  final String connector;
  final List<DatabaseFilter> filters;
}

final class _DatabaseFilterRaw extends DatabaseFilter {
  const _DatabaseFilterRaw(this.sql, this.arguments);

  final String sql;
  final List<DatabaseType> arguments;
}

(String, List<DatabaseType>) _renderDatabaseFilter(DatabaseFilter filter) {
  switch (filter) {
    case _DatabaseFilterComparison(:final column, :final operator, :final value):
      return ('${_quotedIdentifier(column)} $operator ?', [value]);
    case _DatabaseFilterIn(:final column, :final values):
      if (values.isEmpty) return ('0', const []);
      return ('${_quotedIdentifier(column)} IN (${List.filled(values.length, '?').join(', ')})', values);
    case _DatabaseFilterNull(:final column, :final isNull):
      return ('${_quotedIdentifier(column)} IS ${isNull ? '' : 'NOT '}NULL', const []);
    case _DatabaseFilterNot(:final filter):
      final (clause, arguments) = _renderDatabaseFilter(filter);
      return ('NOT ($clause)', arguments);
    case _DatabaseFilterCombination(:final connector, :final filters):
      if (filters.isEmpty) return (connector == 'AND' ? '1' : '0', const []);
      final clauses = <String>[];
      final arguments = <DatabaseType>[];
      for (final filter in filters) {
        final (clause, filterArguments) = _renderDatabaseFilter(filter);
        clauses.add('($clause)');
        arguments.addAll(filterArguments);
      }
      return (clauses.join(' $connector '), arguments);
    case _DatabaseFilterRaw(:final sql, :final arguments):
      return (sql, arguments);
  }
}

/// Composes one [DatabaseFilter], handed to the callback
/// [DatabaseQueryFrom.where], [DatabaseUpdateSet.where] and
/// [DatabaseDeleteFrom.where] each take. Every method answers a leaf
/// [DatabaseFilter]; [and], [or] and [not] combine several into one.
///
/// ```dart
/// db.query<Todo>(
///   (q) => q.from('todos').where((w) => w.isEqualTo(key: 'done', value: DatabaseType.boolean(false))).map(Todo.fromRow),
/// );
/// ```
final class DatabaseFilterBuilder {
  /// Builds no filter on its own; each of its methods does.
  const DatabaseFilterBuilder();

  /// Rows where [key] equals [value].
  DatabaseFilter isEqualTo({required String key, required DatabaseType value}) =>
      _DatabaseFilterComparison(key, '=', value);

  /// Rows where [key] differs from [value].
  DatabaseFilter isNotEqualTo({required String key, required DatabaseType value}) =>
      _DatabaseFilterComparison(key, '!=', value);

  /// Rows where [key] is strictly greater than [value].
  DatabaseFilter isGreaterThan({required String key, required DatabaseType value}) =>
      _DatabaseFilterComparison(key, '>', value);

  /// Rows where [key] is greater than [value], or equal to it.
  DatabaseFilter isGreaterThanOrEqualTo({required String key, required DatabaseType value}) =>
      _DatabaseFilterComparison(key, '>=', value);

  /// Rows where [key] is strictly less than [value].
  DatabaseFilter isLessThan({required String key, required DatabaseType value}) =>
      _DatabaseFilterComparison(key, '<', value);

  /// Rows where [key] is less than [value], or equal to it.
  DatabaseFilter isLessThanOrEqualTo({required String key, required DatabaseType value}) =>
      _DatabaseFilterComparison(key, '<=', value);

  /// Rows where [key] matches [pattern], where `%` stands for any run of
  /// characters and `_` for exactly one.
  DatabaseFilter isLike({required String key, required String pattern}) =>
      _DatabaseFilterComparison(key, 'LIKE', DatabaseType.varchar(pattern));

  /// Rows where [key] is one of [values].
  DatabaseFilter isIn({required String key, required List<DatabaseType> values}) => _DatabaseFilterIn(key, values);

  /// Rows where [key] carries no value.
  DatabaseFilter isNull(String key) => _DatabaseFilterNull(key, true);

  /// Rows where [key] carries a value.
  DatabaseFilter isNotNull(String key) => _DatabaseFilterNull(key, false);

  /// Rows every one of [filters] matches. `AND`s nothing, and matches every
  /// row, when [filters] is empty.
  DatabaseFilter and(List<DatabaseFilter> filters) => _DatabaseFilterCombination('AND', filters);

  /// Rows at least one of [filters] matches. Matches no row when [filters]
  /// is empty.
  DatabaseFilter or(List<DatabaseFilter> filters) => _DatabaseFilterCombination('OR', filters);

  /// Rows [filter] does not match.
  DatabaseFilter not(DatabaseFilter filter) => _DatabaseFilterNot(filter);

  /// A raw SQL predicate, every `?` in it bound to [arguments] in order, for
  /// a condition the rest of this builder cannot express.
  ///
  /// Nothing here validates it, the same choice pylon makes for every other
  /// raw SQL fragment a caller supplies.
  DatabaseFilter raw(String sql, [List<DatabaseType>? arguments]) => _DatabaseFilterRaw(sql, arguments ?? const []);
}
