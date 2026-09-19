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

/// One condition on a [Query], or several combined. Never built directly:
/// [Query.where] hands a [FilterBuilder] to its callback, and every filter
/// comes out of that.
///
/// ```dart
/// users.where((w) => w.or([
///   w(User.age_).isLessThan(13),
///   w.and([w(User.country_).isEqualTo('FR'), w(User.vip_).isEqualTo(true)]),
/// ]))
/// ```
///
/// A field that is missing from a document reads as `null`, the same as one
/// holding `null`: [FieldConditions.isNull] matches both.
sealed class Filter {
  const Filter._();

  _Compiled _compile();
}

/// Composes one [Filter], handed to the callback [Query.where] takes.
///
/// `w(field)` opens the conditions a single field can meet — typed on what the
/// field holds, so its value can only be of that type — and [and], [or] and
/// [not] combine finished filters into one. A [ListField] is opened with
/// [list] instead, since a list is asked different questions.
final class FilterBuilder {
  const FilterBuilder._();

  /// The conditions [field] can meet, each taking a [V].
  FieldConditions<V> call<V extends Object>(Field<V> field) => FieldConditions._(field);

  /// The conditions [field] can meet, on the [E]s it holds.
  ListConditions<E> list<E extends Object>(ListField<E> field) => ListConditions._(field);

  /// Documents every one of [filters] matches. Throws an [ArgumentError] when
  /// [filters] is empty.
  Filter and(List<Filter> filters) => _CompositeFilter('AND', filters);

  /// Documents at least one of [filters] matches. Throws an [ArgumentError]
  /// when [filters] is empty.
  Filter or(List<Filter> filters) => _CompositeFilter('OR', filters);

  /// Documents [filter] does not match — those it cannot decide on included:
  /// a document lacking a field matches neither `isEqualTo` nor
  /// `isGreaterThan` against a value, so it matches [not] of either.
  Filter not(Filter filter) => _NotFilter(filter);
}

/// The conditions on one [Field], opened by `w(field)`. Every value is a [V].
final class FieldConditions<V extends Object> {
  const FieldConditions._(this._field);

  final Field<V> _field;

  /// The field equals [value].
  Filter isEqualTo(V value) => _FieldFilter(_field, isEqualTo: value);

  /// The field is set and differs from [value].
  Filter isNotEqualTo(V value) => _FieldFilter(_field, isNotEqualTo: value);

  /// The field equals one of [values]. Throws an [ArgumentError] when [values]
  /// is empty.
  Filter isIn(List<V> values) => _FieldFilter(_field, whereIn: values);

  /// The field is set and equals none of [values]. Throws an [ArgumentError]
  /// when [values] is empty.
  Filter isNotIn(List<V> values) => _FieldFilter(_field, whereNotIn: values);

  /// The field is missing, or `null`.
  Filter isNull() => _FieldFilter(_field, isNull: true);

  /// The field is set.
  Filter isNotNull() => _FieldFilter(_field, isNull: false);
}

/// The comparisons that need an order, available only on a field whose Dart
/// type has one that matches the order its stored form sorts in: a number, a
/// [String], a [DateTime]. A [bool] and an [Enum] have none — an enum is
/// stored by name, which sorts alphabetically, not in declaration order — so
/// `w(isActive).isGreaterThan(true)` does not compile.
extension OrderedConditions<V extends Comparable<Object?>> on FieldConditions<V> {
  /// The field is below [value].
  Filter isLessThan(V value) => _FieldFilter(_field, isLessThan: value);

  /// The field is at most [value].
  Filter isLessThanOrEqualTo(V value) => _FieldFilter(_field, isLessThanOrEqualTo: value);

  /// The field is above [value].
  Filter isGreaterThan(V value) => _FieldFilter(_field, isGreaterThan: value);

  /// The field is at least [value].
  Filter isGreaterThanOrEqualTo(V value) => _FieldFilter(_field, isGreaterThanOrEqualTo: value);

  /// The field lies between [low] and [high], both included.
  Filter isBetween(V low, V high) => _CompositeFilter('AND', [isGreaterThanOrEqualTo(low), isLessThanOrEqualTo(high)]);
}

/// What a text field can be asked on top of [FieldConditions]. `%` and `_` in
/// the text given match themselves, and SQLite ignores the case of ASCII
/// letters here.
extension TextConditions on FieldConditions<String> {
  /// The field holds [text] somewhere in it.
  Filter contains(String text) => _TextFilter(_field, '%${_escapeLike(text)}%');

  /// The field begins with [text].
  Filter startsWith(String text) => _TextFilter(_field, '${_escapeLike(text)}%');

  /// The field ends with [text].
  Filter endsWith(String text) => _TextFilter(_field, '%${_escapeLike(text)}');
}

/// The conditions on one [ListField], opened by `w.list(field)`. Every element
/// is an [E].
final class ListConditions<E extends Object> {
  const ListConditions._(this._field);

  final ListField<E> _field;

  /// The list contains [element].
  Filter arrayContains(E element) => _FieldFilter(_field, arrayContains: element);

  /// The list contains at least one of [elements]. Throws an [ArgumentError]
  /// when [elements] is empty.
  Filter arrayContainsAny(List<E> elements) => _FieldFilter(_field, arrayContainsAny: elements);

  /// The field is missing, or `null`.
  Filter isNull() => _FieldFilter(_field, isNull: true);

  /// The field is set.
  Filter isNotNull() => _FieldFilter(_field, isNull: false);
}

final class _FieldFilter extends Filter {
  const _FieldFilter(
    this.field, {
    this.isEqualTo,
    this.isNotEqualTo,
    this.isLessThan,
    this.isLessThanOrEqualTo,
    this.isGreaterThan,
    this.isGreaterThanOrEqualTo,
    this.arrayContains,
    this.arrayContainsAny,
    this.whereIn,
    this.whereNotIn,
    this.isNull,
  }) : super._();

  final FieldReference field;
  final Object? isEqualTo;
  final Object? isNotEqualTo;
  final Object? isLessThan;
  final Object? isLessThanOrEqualTo;
  final Object? isGreaterThan;
  final Object? isGreaterThanOrEqualTo;
  final Object? arrayContains;
  final Iterable<Object?>? arrayContainsAny;
  final Iterable<Object?>? whereIn;
  final Iterable<Object?>? whereNotIn;
  final bool? isNull;

  @override
  _Compiled _compile() {
    final expression = _fieldExpression(field);
    final parts = <String>[];
    final args = <DatabaseType>[];

    void compare(String operator, Object? value) {
      parts.add('$expression $operator ?');
      args.add(_operand(value));
    }

    List<DatabaseType> operands(Iterable<Object?> values, String name) {
      final list = values.map(_operand).toList();
      if (list.isEmpty) throw ArgumentError.value(values, name, 'cannot be empty');
      return list;
    }

    if (isEqualTo != null) compare('=', isEqualTo);
    if (isNotEqualTo != null) compare('!=', isNotEqualTo);
    if (isLessThan != null) compare('<', isLessThan);
    if (isLessThanOrEqualTo != null) compare('<=', isLessThanOrEqualTo);
    if (isGreaterThan != null) compare('>', isGreaterThan);
    if (isGreaterThanOrEqualTo != null) compare('>=', isGreaterThanOrEqualTo);
    if (arrayContains != null) {
      parts.add('EXISTS (SELECT 1 FROM json_each(data, ${_jsonPathLiteral(field)}) WHERE value = ?)');
      args.add(_operand(arrayContains));
    }
    if (arrayContainsAny != null) {
      final values = operands(arrayContainsAny!, 'arrayContainsAny');
      parts.add(
        'EXISTS (SELECT 1 FROM json_each(data, ${_jsonPathLiteral(field)}) '
        'WHERE value IN (${_placeholders(values.length)}))',
      );
      args.addAll(values);
    }
    if (whereIn != null) {
      final values = operands(whereIn!, 'isIn');
      parts.add('$expression IN (${_placeholders(values.length)})');
      args.addAll(values);
    }
    if (whereNotIn != null) {
      final values = operands(whereNotIn!, 'isNotIn');
      parts.add('($expression IS NOT NULL AND $expression NOT IN (${_placeholders(values.length)}))');
      args.addAll(values);
    }
    if (isNull != null) parts.add('$expression IS ${isNull! ? '' : 'NOT '}NULL');

    return (sql: parts.length == 1 ? parts.single : '(${parts.join(' AND ')})', args: args);
  }
}

final class _TextFilter extends Filter {
  const _TextFilter(this.field, this.pattern) : super._();

  final Field<String> field;
  final String pattern;

  @override
  _Compiled _compile() => (sql: "${_fieldExpression(field)} LIKE ? ESCAPE '\\'", args: [DatabaseType.varchar(pattern)]);
}

final class _NotFilter extends Filter {
  const _NotFilter(this.filter) : super._();

  final Filter filter;

  @override
  _Compiled _compile() {
    final compiled = filter._compile();
    return (sql: 'NOT COALESCE((${compiled.sql}), 0)', args: compiled.args);
  }
}

final class _CompositeFilter extends Filter {
  const _CompositeFilter(this.operator, this.filters) : super._();

  final String operator;
  final List<Filter> filters;

  @override
  _Compiled _compile() {
    if (filters.isEmpty) throw ArgumentError.value(filters, 'filters', 'cannot be empty');
    final compiled = filters.map((filter) => filter._compile()).toList();
    return (sql: '(${compiled.map((c) => c.sql).join(' $operator ')})', args: [for (final c in compiled) ...c.args]);
  }
}
