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

/// Opens one [LocalDatabase.delete] (or [DatabaseBatch.delete]) call. Never
/// constructed directly — [LocalDatabase.delete] hands one to its own
/// callback. The only method here is [from]: nothing can follow `DELETE`
/// before naming a table, so nothing else is offered here either.
///
/// ```dart
/// final removed = await db.delete((d) => d.from('todos').where((w) => w.isEqualTo(key: 'done', value: DatabaseType.boolean(true))));
/// ```
final class DatabaseDelete {
  const DatabaseDelete._();

  /// Removes rows from [name], the same `FROM` a raw `DELETE FROM ...` names.
  DatabaseDeleteFrom from(String name) => DatabaseDeleteFrom._(_quotedIdentifier(name));
}

/// A [DatabaseDelete] that has named its table, opened by [DatabaseDelete.from] —
/// already a fully composed delete, since `WHERE` is genuinely optional on
/// a raw `DELETE FROM table` (it removes every row without one).
final class DatabaseDeleteFrom {
  DatabaseDeleteFrom._(this._table, [this._where, this._whereArgs]);

  final String _table;
  final String? _where;
  final List<DatabaseType>? _whereArgs;

  /// Keeps only the rows [build] matches, composed from an empty
  /// [DatabaseFilterBuilder]. Called again, both conditions must hold. Every row
  /// in the table is removed when this is never called.
  DatabaseDeleteFrom where(DatabaseFilter Function(DatabaseFilterBuilder w) build) {
    final (clause, arguments) = _renderDatabaseFilter(build(const DatabaseFilterBuilder()));
    return DatabaseDeleteFrom._(_table, _bothMatch(_where, clause), [...?_whereArgs, ...arguments]);
  }
}
