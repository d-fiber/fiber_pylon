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

/// Which way an [IndexColumn] sorts. Ascending, SQLite's own default, when
/// left out entirely.
enum IndexOrder {
  /// Smallest first.
  asc,

  /// Largest first.
  desc,
}

/// One column an index covers, spelled out rather than left as a bare name,
/// for an entry that needs a collation or its own sort order.
final class IndexColumn extends Equatable {
  /// Wraps [expression], [collation] and [order] directly, rather than through a builder — this is the leaf entry [TableIndexBuilder.columns] itself takes.
  const IndexColumn(this.expression, {this.collation, this.order});

  /// The raw SQL expression this entry covers, most often a bare column
  /// name.
  ///
  /// Nothing here validates it, the same choice [ColumnBuilder.default_]
  /// makes for raw SQL no closed vocabulary covers — an expression a bare
  /// column name cannot express, `"lower(email)"`, belongs here just as
  /// well as a plain column would.
  final String expression;

  /// The collating sequence this entry sorts and compares under. SQLite's
  /// own default for its type when left out.
  final String? collation;

  /// The order this entry sorts in. Ascending when left out, SQLite's own
  /// default.
  final IndexOrder? order;

  @override
  List<Object?> get props => [expression, collation, order];
}

/// An index exactly as a [TableIndexBuilder] resolved it, read by
/// [DeclaredTable] to render its own `CREATE INDEX`.
final class TableIndex extends Equatable {
  /// Wraps every field a [TableIndexBuilder] call resolved.
  const TableIndex({required this.name, required this.columns, this.unique = false, this.where});

  /// The name this index is created under.
  final String name;

  /// The columns this index covers, in the order SQLite will list them, at
  /// least one.
  final List<IndexColumn> columns;

  /// Whether this index refuses a row whose covered columns match one
  /// already stored.
  final bool unique;

  /// Restricts the index to the rows where this raw SQL predicate holds,
  /// making it a partial index. Covers every row when left out.
  ///
  /// Nothing here validates it, the same choice [ColumnBuilder.default_]
  /// makes for raw SQL no closed vocabulary covers.
  final String? where;

  @override
  List<Object?> get props => [name, columns, unique, where];
}

/// Opens an index, named `name`, closed once [TableIndexBuilder.columns] has
/// named what it covers and [TableBuilder.indexes]' own callback returns.
final class TableIndexFactory {
  /// Opens no index on its own; [name] does.
  const TableIndexFactory();

  /// The name this index is created under.
  TableIndexBuilder name(String name) => TableIndexBuilder._(name);
}

/// An index under construction, opened by [TableIndexFactory.name].
final class TableIndexBuilder {
  TableIndexBuilder._(this._name);

  final String _name;
  List<IndexColumn>? _columns;
  bool _unique = false;
  String? _where;

  /// The columns this index covers, in the order SQLite will list them, at
  /// least one.
  ///
  /// A bare [String] is read as an [IndexColumn.expression] with no
  /// collation and no explicit order; reach for [IndexColumn] itself only
  /// when an entry needs one of those.
  TableIndexBuilder columns(List<Object> columns) {
    _columns = columns.map((column) => column is IndexColumn ? column : IndexColumn(column as String)).toList();
    return this;
  }

  /// Refuses a row whose covered columns match one already stored.
  TableIndexBuilder unique() {
    _unique = true;
    return this;
  }

  /// Restricts this index to the rows where this raw SQL predicate holds,
  /// making it a partial index. Covers every row when left out.
  TableIndexBuilder where(String predicate) {
    _where = predicate;
    return this;
  }

  /// This index, exactly as [TableBuilder.indexes] reads it once its own
  /// callback returns.
  ///
  /// Throws a [StateError] when [columns] was never called: an index over
  /// nothing is refused here, not once [DeclaredTable.statements] tries to
  /// render it.
  TableIndex _build() {
    final columns = _columns ?? (throw StateError('TableIndexBuilder.columns was never called.'));
    return TableIndex(name: _name, columns: columns, unique: _unique, where: _where);
  }
}
