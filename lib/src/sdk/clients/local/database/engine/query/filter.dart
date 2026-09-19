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

/// One condition a row must meet to be selected, updated or removed.
///
/// A filter is composed by a [FilterBuilder], which [QueryFrom.where],
/// [UpdateSet.where] and [DeleteFrom.where] hand to their callback, or joined
/// to another with the operators `&`, `|` and `~`.
sealed class Filter {
  const Filter();

  /// A filter that a row meets when it meets every one of [filters].
  ///
  /// Every row meets it when [filters] is empty. It suits a list of conditions
  /// assembled at run time, where `&` would need a loop.
  factory Filter.all(List<Filter> filters) => _FilterCombination(_Connector.and, filters);

  /// A filter that a row meets when it meets at least one of [filters].
  ///
  /// No row meets it when [filters] is empty.
  factory Filter.any(List<Filter> filters) => _FilterCombination(_Connector.or, filters);

  /// A filter written as the SQL condition [sql], each `?` in it bound to the
  /// next of [arguments].
  ///
  /// [sql] is not validated, and is not checked against the table the filter
  /// is used on.
  factory Filter.raw(String sql, [List<Value>? arguments]) => _FilterRaw(sql, arguments ?? const []);

  /// A filter that a row meets when it meets both this filter and [other].
  Filter operator &(Filter other) => _FilterCombination(_Connector.and, [this, other]);

  /// A filter that a row meets when it meets this filter or [other].
  Filter operator |(Filter other) => _FilterCombination(_Connector.or, [this, other]);

  /// A filter that a row meets when it does not meet this filter, as
  /// [FilterBuilder.not] does.
  Filter operator ~() => _FilterNot(this);

  /// The tables of the typed columns this filter reads, empty for one built
  /// from plain names.
  ///
  /// The typed tables read it to refuse a filter built from another table.
  Set<String> get _tables => const {};
}

enum _Comparison {
  equal('='),

  /// `IS NOT` rather than `<>`, so that a null differs from every value.
  notEqual('IS NOT'),
  greaterThan('>'),
  greaterThanOrEqual('>='),
  lessThan('<'),
  lessThanOrEqual('<='),
  like('LIKE');

  const _Comparison(this.sql);

  final String sql;
}

enum _Connector {
  and('AND', '1'),
  or('OR', '0');

  const _Connector(this.sql, this.whenEmpty);

  final String sql;
  final String whenEmpty;
}

final class _FilterComparison extends Filter {
  const _FilterComparison(this.column, this.comparison, this.value);

  final String column;
  final _Comparison comparison;
  final Value value;
}

final class _FilterLike extends Filter {
  const _FilterLike(this.column, this.pattern);

  final String column;
  final String pattern;
}

final class _FilterIn extends Filter {
  const _FilterIn(this.column, this.values);

  final String column;
  final List<Value> values;
}

final class _FilterNull extends Filter {
  const _FilterNull(this.column, this.isNull);

  final String column;
  final bool isNull;
}

final class _FilterNot extends Filter {
  const _FilterNot(this.filter);

  final Filter filter;

  @override
  Set<String> get _tables => filter._tables;
}

final class _FilterOfTable extends Filter {
  const _FilterOfTable(this.filter, this.table);

  final Filter filter;
  final String table;

  @override
  Set<String> get _tables => {table};
}

final class _FilterCombination extends Filter {
  const _FilterCombination(this.connector, this.filters);

  final _Connector connector;
  final List<Filter> filters;

  @override
  Set<String> get _tables => {for (final filter in filters) ...filter._tables};
}

final class _FilterRaw extends Filter {
  const _FilterRaw(this.sql, this.arguments);

  final String sql;
  final List<Value> arguments;
}

String _likeText(String text, String name) => text.contains('\u0000')
    ? throw ArgumentError.value(text, name, 'SQLite reads a NUL as the end of a LIKE pattern, so it would match more.')
    : text;

String _bothMatch(String? earlier, String later) => earlier == null ? later : '($earlier) AND ($later)';

String _escapeLike(String text) => text.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

Value _orderable(Value value) => value is Nil
    ? throw ArgumentError.value(value, 'value', 'NULL has no order to compare against. Use isNull or isNotNull.')
    : value;

/// The SQL condition for [filter] and the values bound to its placeholders.
///
/// A [_FilterNot] is wrapped so that a row the inner condition cannot decide
/// on, one where it reads null, counts as not meeting it and so meets the not.
(String, List<Value>) _renderDatabaseFilter(Filter filter) {
  switch (filter) {
    case _FilterComparison(:final column, :final comparison, :final value):
      final name = _quotedIdentifier(column);
      return switch ((comparison, value)) {
        (_Comparison.equal, Nil()) => ('$name IS NULL', const []),
        (_Comparison.notEqual, Nil()) => ('$name IS NOT NULL', const []),
        _ => ('$name ${comparison.sql} ?', [value]),
      };
    case _FilterLike(:final column, :final pattern):
      return ("${_quotedIdentifier(column)} LIKE ? ESCAPE '\\'", [Value.varchar(pattern)]);
    case _FilterIn(:final column, :final values):
      final name = _quotedIdentifier(column);
      final present = values.where((value) => value is! Nil).toList();
      final clauses = [
        if (present.isNotEmpty) '$name IN (${List.filled(present.length, '?').join(', ')})',
        if (present.length != values.length) '$name IS NULL',
      ];
      return switch (clauses) {
        [] => ('0', const []),
        [final single] => (single, present),
        _ => ('(${clauses.join(' OR ')})', present),
      };
    case _FilterNull(:final column, :final isNull):
      return ('${_quotedIdentifier(column)} IS ${isNull ? '' : 'NOT '}NULL', const []);
    case _FilterOfTable(:final filter):
      return _renderDatabaseFilter(filter);
    case _FilterNot(:final filter):
      final (clause, arguments) = _renderDatabaseFilter(filter);
      return ('NOT COALESCE(($clause), 0)', arguments);
    case _FilterCombination(:final connector, :final filters):
      if (filters.isEmpty) return (connector.whenEmpty, const []);
      final clauses = <String>[];
      final arguments = <Value>[];
      for (final filter in filters) {
        final (clause, filterArguments) = _renderDatabaseFilter(filter);
        clauses.add('($clause)');
        arguments.addAll(filterArguments);
      }
      return (clauses.join(' ${connector.sql} '), arguments);
    case _FilterRaw(:final sql, :final arguments):
      return (sql, arguments);
  }
}

/// The methods that compose a [Filter], one condition each, and combine
/// several into one with [and], [or] and [not].
///
/// [QueryFrom.where], [QueryFrom.having], [UpdateSet.where] and
/// [DeleteFrom.where] hand one to their callback.
///
/// ```dart
/// LocalDatabase.query<Todo>(
///   (q) => q.from('todos').where((w) => w.isEqualTo(key: 'done', value: Value.boolean(false))).map(Todo.fromRow),
/// );
/// ```
///
/// What a condition can say depends on how the [Value] is stored. [isEqualTo],
/// [isNotEqualTo] and [isIn] work on every one. The ordering methods, such as
/// [isGreaterThan], give the order a person expects on a boolean, a timestamp,
/// a date, a number, a text, a [Value.time] and a blob. On a [Value.enum_] they
/// compare the member names alphabetically, not in declaration order, so to
/// filter on "after spring" pass [isIn] the later members. A list, a shape, an
/// interval or a range is stored as JSON text, so equality holds only for the
/// exact same text, and anything finer, such as whether a range contains a
/// value, goes through [raw].
final class FilterBuilder {
  /// A builder, which holds nothing: each method answers a new [Filter].
  const FilterBuilder();

  /// A filter on the rows where [key] equals [value].
  ///
  /// When [value] is a [Nil] it matches the rows where [key] is null, which a
  /// plain SQL `=` never would.
  Filter isEqualTo({required String key, required Value value}) => _FilterComparison(key, _Comparison.equal, value);

  /// A filter on the rows where [key] differs from [value].
  ///
  /// The rows where [key] is null are included, since a null differs from every
  /// value. When [value] is a [Nil] it matches the rows where [key] is not
  /// null.
  Filter isNotEqualTo({required String key, required Value value}) =>
      _FilterComparison(key, _Comparison.notEqual, value);

  /// A filter on the rows where [key] is strictly greater than [value].
  ///
  /// A row where [key] is null never matches. Throws an [ArgumentError] when
  /// [value] is a [Nil], which has no order.
  Filter isGreaterThan({required String key, required Value value}) =>
      _FilterComparison(key, _Comparison.greaterThan, _orderable(value));

  /// A filter on the rows where [key] is greater than or equal to [value].
  ///
  /// A row where [key] is null never matches. Throws an [ArgumentError] when
  /// [value] is a [Nil], which has no order.
  Filter isGreaterThanOrEqualTo({required String key, required Value value}) =>
      _FilterComparison(key, _Comparison.greaterThanOrEqual, _orderable(value));

  /// A filter on the rows where [key] is strictly less than [value].
  ///
  /// A row where [key] is null never matches. Throws an [ArgumentError] when
  /// [value] is a [Nil], which has no order.
  Filter isLessThan({required String key, required Value value}) =>
      _FilterComparison(key, _Comparison.lessThan, _orderable(value));

  /// A filter on the rows where [key] is less than or equal to [value].
  ///
  /// A row where [key] is null never matches. Throws an [ArgumentError] when
  /// [value] is a [Nil], which has no order.
  Filter isLessThanOrEqualTo({required String key, required Value value}) =>
      _FilterComparison(key, _Comparison.lessThanOrEqual, _orderable(value));

  /// A filter on the rows where [key] matches [pattern], in which `%` stands
  /// for any run of characters and `_` for exactly one.
  ///
  /// A `%` or `_` in text a user typed matches more than itself, so use
  /// [contains], [startsWith] or [endsWith] to match text as it is. The case of
  /// ASCII letters is ignored.
  ///
  /// Throws an [ArgumentError] when [pattern] holds a NUL character, which
  /// SQLite reads as the end of the pattern.
  Filter isLike({required String key, required String pattern}) =>
      _FilterComparison(key, _Comparison.like, Value.varchar(_likeText(pattern, 'pattern')));

  /// A filter on the rows where [key] holds [text] somewhere in it.
  ///
  /// A `%` or `_` in [text] matches itself. The case of ASCII letters is
  /// ignored.
  ///
  /// Throws an [ArgumentError] when [text] holds a NUL character, which SQLite
  /// reads as the end of a pattern, so it would match every row.
  Filter contains({required String key, required String text}) =>
      _FilterLike(key, '%${_escapeLike(_likeText(text, 'text'))}%');

  /// A filter on the rows where [key] begins with [text].
  ///
  /// A `%` or `_` in [text] matches itself. The case of ASCII letters is
  /// ignored.
  ///
  /// Throws an [ArgumentError] when [text] holds a NUL character, as [contains]
  /// does.
  Filter startsWith({required String key, required String text}) =>
      _FilterLike(key, '${_escapeLike(_likeText(text, 'text'))}%');

  /// A filter on the rows where [key] ends with [text].
  ///
  /// A `%` or `_` in [text] matches itself. The case of ASCII letters is
  /// ignored.
  ///
  /// Throws an [ArgumentError] when [text] holds a NUL character, as [contains]
  /// does.
  Filter endsWith({required String key, required String text}) =>
      _FilterLike(key, '%${_escapeLike(_likeText(text, 'text'))}');

  /// A filter on the rows where [key] is one of [values].
  ///
  /// A [Nil] among them matches the rows where [key] is null. No row matches
  /// when [values] is empty.
  Filter isIn({required String key, required List<Value> values}) => _FilterIn(key, values);

  /// A filter on the rows where [key] is null.
  Filter isNull(String key) => _FilterNull(key, true);

  /// A filter on the rows where [key] is not null.
  Filter isNotNull(String key) => _FilterNull(key, false);

  /// A filter on the rows that meet every one of [filters].
  ///
  /// Every row meets it when [filters] is empty.
  Filter and(List<Filter> filters) => _FilterCombination(_Connector.and, filters);

  /// A filter on the rows that meet at least one of [filters].
  ///
  /// No row meets it when [filters] is empty.
  Filter or(List<Filter> filters) => _FilterCombination(_Connector.or, filters);

  /// A filter on the rows that do not meet [filter].
  ///
  /// That includes the rows [filter] cannot decide on. A row where a column is
  /// null meets neither [isEqualTo] nor [isGreaterThan] against a value, so it
  /// meets [not] of either.
  Filter not(Filter filter) => _FilterNot(filter);

  /// A filter written as the SQL condition [sql], each `?` in it bound to the
  /// next of [arguments], for what the other methods cannot express.
  ///
  /// [sql] is not validated, as with every raw SQL fragment this package takes.
  Filter raw(String sql, [List<Value>? arguments]) => _FilterRaw(sql, arguments ?? const []);
}
