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

/// The same [LocalDatabase.insert], [LocalDatabase.query],
/// [LocalDatabase.update] and [LocalDatabase.delete] a [LocalDatabase]
/// offers, scoped to one [LocalDatabase.transaction]. Never constructed
/// directly; [LocalDatabase.transaction] hands one to its own callback.
final class DatabaseTransaction extends DatabaseSession {
  DatabaseTransaction._(this._txn, this._owner);

  final Transaction _txn;
  final LocalDatabase _owner;

  @override
  LocalDatabase get _database => _owner;

  @override
  DatabaseExecutor _executor() => _txn;

  @override
  Future<T> _atomically<T>(Future<T> Function(DatabaseSession session) action) => action(this);

  /// See [LocalDatabase.execute].
  Future<void> execute(String sql, [List<DatabaseType>? arguments]) => _guarded(() async {
    await _txn.execute(sql, _toNativeArgs(arguments));
    _owner._notifyWrite(null);
  });

  /// See [LocalDatabase.insert].
  Future<int> insert<T extends DatabaseRecord>(DatabaseInsertValues<T> Function(DatabaseInsert<T> insert) build) =>
      _guarded(() async {
        final spec = build(DatabaseInsert<T>._());
        final rowId = await _txn.rawInsert(spec._sql, spec._arguments);
        _owner._notifyWrite({_unquotedIdentifier(spec._table)});
        return rowId;
      });

  /// See [LocalDatabase.query].
  Future<List<T>> query<T extends Object>(DatabaseQueryFrom<T> Function(DatabaseQuery<T> query) build) =>
      _guarded(() async {
        final spec = build(DatabaseQuery<T>._());
        final rows = await _txn.query(
          spec._table,
          distinct: spec._distinct,
          columns: spec._columns,
          where: spec._where,
          whereArgs: _toNativeArgs(spec._arguments),
          groupBy: spec._groupBy,
          having: spec._having,
          orderBy: spec._orderBy,
          limit: spec._limit,
          offset: spec._offset,
        );
        final fromRow = spec._requiredFromRow;
        return rows.map((row) => fromRow(_fromNativeRow(row))).toList();
      });

  /// See [LocalDatabase.rawQuery].
  Future<List<DatabaseRow>> rawQuery(String sql, [List<DatabaseType>? arguments]) => _guarded(() async {
    final rows = await _txn.rawQuery(sql, _toNativeArgs(arguments));
    return rows.map(_fromNativeRow).toList();
  });

  /// See [LocalDatabase.update].
  Future<int> update<T extends DatabaseRecord>(DatabaseUpdateSet<T> Function(DatabaseUpdate<T> update) build) =>
      _guarded(() async {
        final spec = build(DatabaseUpdate<T>._());
        final changed = await _txn.update(
          spec._table,
          _toNativeRow(spec._data.toRow()),
          where: spec._where,
          whereArgs: _toNativeArgs(spec._whereArgs),
          conflictAlgorithm: spec._conflict,
        );
        if (changed > 0) _owner._notifyWrite({_unquotedIdentifier(spec._table)});
        return changed;
      });

  /// See [LocalDatabase.delete].
  Future<int> delete(DatabaseDeleteFrom Function(DatabaseDelete delete) build) => _guarded(() async {
    final spec = build(const DatabaseDelete._());
    final removed = await _txn.delete(spec._table, where: spec._where, whereArgs: _toNativeArgs(spec._whereArgs));
    if (removed > 0) _owner._notifyWrite({_unquotedIdentifier(spec._table)});
    return removed;
  });
}
