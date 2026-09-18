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

/// A table-level `FOREIGN KEY` constraint spanning one or several columns at
/// once.
final class TableForeignKey extends Equatable {
  /// Wraps every field a [TableForeignKeyBuilder] call resolved.
  const TableForeignKey({
    required this.columns,
    required this.referencedTable,
    this.referencedColumns,
    this.onDelete,
    this.onUpdate,
    this.deferrable = false,
    this.initiallyDeferred = false,
    this.name,
  });

  /// The columns of this table that, together, form the key.
  final List<String> columns;

  /// The table [columns] points at.
  final String referencedTable;

  /// The columns of [referencedTable] this key points at, in the same order
  /// as [columns]. Its primary key when left out.
  final List<String>? referencedColumns;

  /// What happens to this row when the referenced row is deleted. Nothing
  /// special when left out.
  final ReferentialAction? onDelete;

  /// What happens to this row when the referenced row's key changes.
  /// Nothing special when left out.
  final ReferentialAction? onUpdate;

  /// Whether this constraint can be checked at the end of the transaction
  /// rather than immediately.
  final bool deferrable;

  /// Whether a deferrable constraint checks at the end of the transaction by
  /// default. Meaningless when [deferrable] is `false`.
  final bool initiallyDeferred;

  /// The name this constraint is created under. SQLite picks one on its
  /// own when left out.
  final String? name;

  @override
  List<Object?> get props => [
    columns,
    referencedTable,
    referencedColumns,
    onDelete,
    onUpdate,
    deferrable,
    initiallyDeferred,
    name,
  ];
}

/// Opens a table-level `FOREIGN KEY` constraint, closed once
/// [TableForeignKeyBuilder.references] has named the table it points at and
/// [TableBuilder.foreignKeys]' own callback returns.
final class TableForeignKeyFactory {
  /// Opens no constraint on its own; [columns] does.
  const TableForeignKeyFactory();

  /// The columns of this table that, together, form the key.
  TableForeignKeyBuilder columns(List<String> columns) => TableForeignKeyBuilder._(columns);
}

/// A table-level `FOREIGN KEY` constraint under construction, opened by
/// [TableForeignKeyFactory.columns].
final class TableForeignKeyBuilder {
  TableForeignKeyBuilder._(this._columns);

  final List<String> _columns;
  String? _referencedTable;
  List<String>? _referencedColumns;
  ReferentialAction? _onDelete;
  ReferentialAction? _onUpdate;
  bool _deferrable = false;
  bool _initiallyDeferred = false;
  String? _name;

  /// The table [TableForeignKeyFactory.columns] points at, and which of its
  /// columns, in the same order. Its primary key when [referencedColumns]
  /// is left out.
  TableForeignKeyBuilder references(String table, [List<String>? referencedColumns]) {
    _referencedTable = table;
    _referencedColumns = referencedColumns;
    return this;
  }

  /// What happens to this row when the referenced row is deleted. Nothing
  /// special when left out.
  TableForeignKeyBuilder onDelete(ReferentialAction action) {
    _onDelete = action;
    return this;
  }

  /// What happens to this row when the referenced row's key changes.
  /// Nothing special when left out.
  TableForeignKeyBuilder onUpdate(ReferentialAction action) {
    _onUpdate = action;
    return this;
  }

  /// Lets this constraint wait until the end of its transaction to be
  /// checked, rather than immediately.
  TableForeignKeyBuilder deferrable([bool initiallyDeferred = false]) {
    _deferrable = true;
    _initiallyDeferred = initiallyDeferred;
    return this;
  }

  /// The name this constraint is created under. SQLite picks one on its
  /// own when left out.
  TableForeignKeyBuilder name(String name) {
    _name = name;
    return this;
  }

  /// This constraint, exactly as [TableBuilder.foreignKeys] reads it once
  /// its own callback returns.
  ///
  /// Throws a [StateError] when [references] was never called: a foreign
  /// key with nothing to point at is refused here, not once
  /// [DeclaredTable.statements] tries to render it.
  TableForeignKey _build() {
    final table = _referencedTable ?? (throw StateError('TableForeignKeyBuilder.references was never called.'));
    return TableForeignKey(
      columns: _columns,
      referencedTable: table,
      referencedColumns: _referencedColumns,
      onDelete: _onDelete,
      onUpdate: _onUpdate,
      deferrable: _deferrable,
      initiallyDeferred: _initiallyDeferred,
      name: _name,
    );
  }
}
