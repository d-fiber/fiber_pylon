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

/// An update that has not yet named its table.
///
/// [LocalDatabase.update] and [StatementBatch.update] hand one to their
/// callback, which names the table with [table], gives the new values with
/// [UpdateTable.set] and returns the result.
///
/// ```dart
/// final changed = await LocalDatabase.update<Todo>(
///   (u) => u.table('todos').set(done).where((w) => w.isEqualTo(key: 'id', value: Value.integer(id))),
/// );
/// ```
final class Update<T extends Storable> {
  Update._();

  /// Updates rows of the table called [name].
  UpdateTable<T> table(String name) => UpdateTable._(_quotedIdentifier(name));
}

/// An update that has named its table and still needs the values to write.
final class UpdateTable<T extends Storable> {
  UpdateTable._(this._table);

  /// The name of the table to update.
  final String _table;

  /// Writes the row [Storable.toRow] gives for [value] over every row the
  /// update matches.
  UpdateSet<T> set(T value) => UpdateSet._(_table, value);
}

/// An update that has its table and its values, and is complete as it stands.
///
/// Without [where] it changes every row of the table. [where] and
/// [onConflict] may be called in either order.
final class UpdateSet<T extends Storable> {
  UpdateSet._(this._table, this._data, [this._where, this._whereArgs, this._conflict]);

  /// The name of the table to update.
  final String _table;

  /// The value whose row is written.
  final T _data;

  /// The condition a row must meet to be updated, or `null` for every row.
  final String? _where;

  /// The values bound to the placeholders of [_where].
  final List<Value>? _whereArgs;

  /// How to resolve a collision with another row, or `null` to abort.
  final ConflictAlgorithm? _conflict;

  /// Updates only the rows [build] matches.
  ///
  /// [build] receives an empty [FilterBuilder]. Called again, a row must meet
  /// both conditions to be updated.
  UpdateSet<T> where(Filter Function(FilterBuilder w) build) {
    final (clause, arguments) = _renderDatabaseFilter(build(const FilterBuilder()));
    return UpdateSet._(_table, _data, _bothMatch(_where, clause), [...?_whereArgs, ...arguments], _conflict);
  }

  /// Resolves a collision between an updated row and another row of the table
  /// with [algorithm].
  ///
  /// Left unset, a collision aborts the statement and throws a
  /// [UniqueConstraintError].
  UpdateSet<T> onConflict(ConflictAlgorithm algorithm) => UpdateSet._(_table, _data, _where, _whereArgs, algorithm);
}
