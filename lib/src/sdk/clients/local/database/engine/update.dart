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

/// Opens one [LocalDatabase.update] (or [DatabaseBatch.update]) call. Never
/// constructed directly — [LocalDatabase.update] hands one to its own
/// callback. The only method here is [table]: nothing can follow `UPDATE`
/// before naming a table, so nothing else is offered here either.
///
/// ```dart
/// final changed = await db.update<Todo>(
///   (u) => u.table('todos').set(done).where((w) => w.isEqualTo(key: 'id', value: DatabaseType.integer(id))),
/// );
/// ```
final class DatabaseUpdate<T extends DatabaseRecord> {
  DatabaseUpdate._();

  /// Updates rows in [name], the same table name a raw `UPDATE table` names.
  DatabaseUpdateTable<T> table(String name) => DatabaseUpdateTable._(_quotedIdentifier(name));
}

/// A [DatabaseUpdate] that has named its table, opened by [DatabaseUpdate.table].
/// The only method here is [set]: a raw `UPDATE table` still needs a `SET`
/// clause before it means anything, so nothing else is offered here either.
final class DatabaseUpdateTable<T extends DatabaseRecord> {
  DatabaseUpdateTable._(this._table);

  final String _table;

  /// Writes [value], read into a row through [DatabaseRecord.toRow], over
  /// every matched row.
  DatabaseUpdateSet<T> set(T value) => DatabaseUpdateSet._(_table, value);
}

/// A fully composed update, opened by [DatabaseUpdateTable.set] — the only
/// shape [LocalDatabase.update] accepts back from its own callback. [where]
/// and [onConflict] refine it further and may be called in either order,
/// since neither changes what the other is allowed to be.
final class DatabaseUpdateSet<T extends DatabaseRecord> {
  DatabaseUpdateSet._(this._table, this._data, [this._where, this._whereArgs, this._conflict]);

  final String _table;
  final T _data;
  final String? _where;
  final List<DatabaseType>? _whereArgs;
  final ConflictAlgorithm? _conflict;

  /// Keeps only the rows [build] matches, composed from an empty
  /// [DatabaseFilterBuilder]. Called again, both conditions must hold. Every row
  /// in the table is matched when this is never called.
  DatabaseUpdateSet<T> where(DatabaseFilter Function(DatabaseFilterBuilder w) build) {
    final (clause, arguments) = _renderDatabaseFilter(build(const DatabaseFilterBuilder()));
    return DatabaseUpdateSet._(_table, _data, _bothMatch(_where, clause), [...?_whereArgs, ...arguments], _conflict);
  }

  /// Resolves the conflict, should [set] collide with a row already there.
  /// Left unset, sqflite aborts the whole statement.
  DatabaseUpdateSet<T> onConflict(ConflictAlgorithm algorithm) =>
      DatabaseUpdateSet._(_table, _data, _where, _whereArgs, algorithm);
}
