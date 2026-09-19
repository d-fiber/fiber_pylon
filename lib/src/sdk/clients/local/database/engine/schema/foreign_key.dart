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

/// A table-level `FOREIGN KEY` constraint that spans one or several columns.
final class TableForeignKey extends Equatable {
  /// Built only by [TableForeignKeyBuilder], which refuses a key that points at
  /// nothing.
  const TableForeignKey._({
    required this.columns,
    required this.referencedTable,
    this.referencedColumns,
    this.onDelete,
    this.onUpdate,
    this.deferral,
    this.name,
  });

  /// The columns of the declared table that, together, hold the reference.
  final List<String> columns;

  /// The table [columns] points at.
  final String referencedTable;

  /// The columns of [referencedTable] this key points at, in the same order as
  /// [columns]. Its primary key when left out.
  final List<String>? referencedColumns;

  /// What happens to a row of the declared table when the row it points at is
  /// deleted. SQLite applies [ReferentialAction.noAction] when left out.
  final ReferentialAction? onDelete;

  /// What happens to a row of the declared table when the key of the row it
  /// points at changes. SQLite applies [ReferentialAction.noAction] when left
  /// out.
  final ReferentialAction? onUpdate;

  /// When this constraint is checked, if it may be checked later than the
  /// statement that broke it. Not deferrable when left out.
  final Deferral? deferral;

  /// The name of this constraint. Unnamed when left out.
  final String? name;

  @override
  List<Object?> get props => [columns, referencedTable, referencedColumns, onDelete, onUpdate, deferral, name];
}

/// The starting point of a table-level `FOREIGN KEY` constraint, handed to the
/// callback of [TableBuilderBase.foreignKeys].
final class TableForeignKeyFactory {
  /// Creates a factory, which [TableBuilderBase.foreignKeys] already supplies to
  /// its callback.
  const TableForeignKeyFactory();

  /// Starts a foreign key held by [columns], columns of the table being
  /// declared.
  ///
  /// The key is not complete until [TableForeignKeyBuilder.references] names the
  /// table it points at.
  TableForeignKeyBuilder columns(List<String> columns) => TableForeignKeyBuilder._(columns);
}

/// A table-level `FOREIGN KEY` constraint under construction, started by
/// [TableForeignKeyFactory.columns] and read by [TableBuilderBase.foreignKeys]
/// once its callback returns.
final class TableForeignKeyBuilder {
  TableForeignKeyBuilder._(this._columns);

  /// Backs [TableForeignKey.columns].
  final List<String> _columns;

  /// Backs [TableForeignKey.referencedTable].
  String? _referencedTable;

  /// Backs [TableForeignKey.referencedColumns].
  List<String>? _referencedColumns;

  /// Backs [TableForeignKey.onDelete].
  ReferentialAction? _onDelete;

  /// Backs [TableForeignKey.onUpdate].
  ReferentialAction? _onUpdate;

  /// Backs [TableForeignKey.deferral].
  Deferral? _deferral;

  /// Backs [TableForeignKey.name].
  String? _name;

  /// Points this key at [table], and at [referencedColumns] of it, matched to
  /// the key's own columns in order.
  ///
  /// The primary key of [table] when [referencedColumns] is left out. Required:
  /// [TableBuilderBase.foreignKeys] throws a [StateError] for a key that never
  /// called it.
  TableForeignKeyBuilder references(String table, [List<String>? referencedColumns]) {
    _referencedTable = table;
    _referencedColumns = referencedColumns;
    return this;
  }

  /// Sets what happens to a row of the declared table when the row it points at
  /// is deleted.
  ///
  /// SQLite applies [ReferentialAction.noAction] when this is not called.
  TableForeignKeyBuilder onDelete(ReferentialAction action) {
    _onDelete = action;
    return this;
  }

  /// Sets what happens to a row of the declared table when the key of the row it
  /// points at changes.
  ///
  /// SQLite applies [ReferentialAction.noAction] when this is not called.
  TableForeignKeyBuilder onUpdate(ReferentialAction action) {
    _onUpdate = action;
    return this;
  }

  /// Lets this constraint be checked later than the statement that broke it, at
  /// the moment [deferral] says.
  TableForeignKeyBuilder deferrable(Deferral deferral) {
    _deferral = deferral;
    return this;
  }

  /// Names this constraint.
  ///
  /// It stays unnamed when this is not called.
  TableForeignKeyBuilder name(String name) {
    _name = name;
    return this;
  }

  /// The finished constraint.
  ///
  /// Throws a [StateError] when [references] was never called, so that a key
  /// with nothing to point at is refused here and not once
  /// [DeclaredTable.statements] tries to render it.
  TableForeignKey _build() {
    final table = _referencedTable ?? (throw StateError('TableForeignKeyBuilder.references was never called.'));
    return TableForeignKey._(
      columns: _columns,
      referencedTable: table,
      referencedColumns: _referencedColumns,
      onDelete: _onDelete,
      onUpdate: _onUpdate,
      deferral: _deferral,
      name: _name,
    );
  }
}
