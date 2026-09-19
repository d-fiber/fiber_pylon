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

/// One entry of an index, with the collation and sort order it carries.
///
/// A name and a piece of raw SQL are told apart by how the entry is built:
/// [IndexColumn.named] takes a column name and quotes it, [IndexColumn.expression]
/// takes SQL and writes it as given. A `switch` over an [IndexColumn] is
/// exhaustive with [NamedIndexColumn] and [ExpressionIndexColumn].
sealed class IndexColumn extends Equatable {
  const IndexColumn._({this.collation, this.order});

  /// An entry covering the column called [name].
  const factory IndexColumn.named(String name, {Collation? collation, SortOrder? order}) = NamedIndexColumn._;

  /// An entry covering the SQL expression [sql], most often an expression over
  /// columns such as `lower(email)`.
  ///
  /// The text is written into the statement as given and is not checked, so a
  /// mistake in it is reported by SQLite when the statement runs.
  const factory IndexColumn.expression(String sql, {Collation? collation, SortOrder? order}) = ExpressionIndexColumn._;

  /// The collation this entry sorts and compares under.
  ///
  /// Left out, a named column keeps the collation it was declared with and an
  /// expression compares as [Collation.binary].
  final Collation? collation;

  /// The order this entry sorts in. [SortOrder.asc] when left out.
  final SortOrder? order;
}

/// An [IndexColumn] that covers one column, by name.
final class NamedIndexColumn extends IndexColumn {
  const NamedIndexColumn._(this.name, {super.collation, super.order}) : super._();

  /// The name of the column this entry covers.
  final String name;

  @override
  List<Object?> get props => [name, collation, order];
}

/// An [IndexColumn] that covers a raw SQL expression.
final class ExpressionIndexColumn extends IndexColumn {
  const ExpressionIndexColumn._(this.sql, {super.collation, super.order}) : super._();

  /// The SQL expression this entry covers.
  final String sql;

  @override
  List<Object?> get props => [sql, collation, order];
}

/// An index as a [TableIndexBuilder] resolved it, which [DeclaredTable] renders
/// as a `CREATE INDEX` statement.
final class TableIndex extends Equatable {
  /// Built only by [TableIndexBuilder], which refuses an index that covers
  /// nothing.
  const TableIndex._({required this.name, required this.columns, this.unique = false, this.where});

  /// The name this index is created under.
  final String name;

  /// The entries this index covers, in the order given.
  ///
  /// Must not be empty: SQLite refuses an index over nothing when the statement
  /// runs.
  final List<IndexColumn> columns;

  /// Whether this index refuses a row whose covered columns match one already
  /// stored.
  ///
  /// A row holding null in a covered column never counts as a match.
  final bool unique;

  /// The raw SQL predicate that restricts this index to the rows it holds
  /// for, which makes it a partial index. Covers every row when left out.
  ///
  /// The text is written into the statement as given and is not checked, so a
  /// mistake in it is reported by SQLite when the statement runs.
  final String? where;

  @override
  List<Object?> get props => [name, columns, unique, where];
}

/// The starting point of an index, handed to the callback of
/// [TableBuilderBase.indexes].
final class TableIndexFactory {
  /// Creates a factory, which [TableBuilderBase.indexes] already supplies to its
  /// callback.
  const TableIndexFactory();

  /// Starts an index called [name].
  ///
  /// The index is not complete until [TableIndexBuilder.columns] says what it
  /// covers.
  TableIndexBuilder name(String name) => TableIndexBuilder._(name);
}

/// An index under construction, started by [TableIndexFactory.name] and read by
/// [TableBuilderBase.indexes] once its callback returns.
final class TableIndexBuilder {
  TableIndexBuilder._(this._name);

  /// Backs [TableIndex.name].
  final String _name;

  /// Backs [TableIndex.columns].
  List<IndexColumn>? _columns;

  /// Backs [TableIndex.unique].
  bool _unique = false;

  /// Backs [TableIndex.where].
  String? _where;

  /// Sets the entries this index covers, in the order given.
  ///
  /// Required, and not empty: [TableBuilderBase.indexes] throws a [StateError]
  /// for an index that never called it.
  TableIndexBuilder columns(List<IndexColumn> columns) {
    _columns = columns;
    return this;
  }

  /// Makes this index refuse a row whose covered columns match one already
  /// stored.
  TableIndexBuilder unique() {
    _unique = true;
    return this;
  }

  /// Restricts this index to the rows where [predicate], a raw SQL condition,
  /// holds, which makes it a partial index.
  TableIndexBuilder where(String predicate) {
    _where = predicate;
    return this;
  }

  /// The finished index.
  ///
  /// Throws a [StateError] when [columns] was never called, so that an index
  /// over nothing is refused here and not once [DeclaredTable.statements] tries
  /// to render it.
  TableIndex _build() {
    final columns = _columns ?? (throw StateError('TableIndexBuilder.columns was never called.'));
    return TableIndex._(name: _name, columns: columns, unique: _unique, where: _where);
  }
}
