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

/// Opens one [LocalDatabase.insert] (or [StatementBatch.insert]) call. Never
/// constructed directly — [LocalDatabase.insert] hands one to its own
/// callback. The only method here is [into]: nothing can follow `INSERT`
/// before naming a table, so nothing else is offered here either — the
/// compiler refuses a callback that returns [Insert] itself, or
/// anything short of a fully composed [InsertValues].
///
/// ```dart
/// final id = await db.insert<Todo>((i) => i.into('todos').values(todo));
/// ```
final class Insert<T extends Storable> {
  Insert._();

  /// Inserts into [name], the same `INTO` a raw `INSERT INTO ...` names.
  InsertInto<T> into(String name) => InsertInto._(_quotedIdentifier(name));
}

/// A [Insert] that has named its table, opened by [Insert.into].
/// The only method here is [values]: a raw `INSERT INTO table` still needs a
/// `VALUES` clause before it means anything, so nothing else is offered
/// here either.
final class InsertInto<T extends Storable> {
  InsertInto._(this._table);

  final String _table;

  /// Inserts [value], read into a row through [Storable.toRow].
  InsertValues<T> values(T value) => InsertValues._(_table, value);
}

/// A fully composed insert, opened by [InsertInto.values] — the only
/// shape [LocalDatabase.insert] accepts back from its own callback, since
/// naming a table and a value is everything a raw `INSERT INTO ... VALUES
/// (...)` needs.
final class InsertValues<T extends Storable> {
  InsertValues._(this._table, this._data, [this._conflict]);

  final String _table;
  final T _data;
  final ConflictAlgorithm? _conflict;

  /// Resolves the conflict, should [values] collide with a row already
  /// there. Left unset, sqflite aborts the whole statement.
  InsertValues<T> onConflict(ConflictAlgorithm algorithm) => InsertValues._(_table, _data, algorithm);

  String get _sql {
    final columns = _data.toRow().keys.map(_quotedIdentifier);
    final verb = 'INSERT ${_conflictClause(_conflict)}INTO $_table';
    if (columns.isEmpty) return '$verb DEFAULT VALUES';
    return '$verb (${columns.join(', ')}) VALUES (${List.filled(columns.length, '?').join(', ')})';
  }

  List<Object?> get _arguments => _data.toRow().values.map((value) => value._toNative()).toList();
}

String _conflictClause(ConflictAlgorithm? algorithm) => switch (algorithm) {
  null => '',
  ConflictAlgorithm.rollback => 'OR ROLLBACK ',
  ConflictAlgorithm.abort => 'OR ABORT ',
  ConflictAlgorithm.fail => 'OR FAIL ',
  ConflictAlgorithm.ignore => 'OR IGNORE ',
  ConflictAlgorithm.replace => 'OR REPLACE ',
};
