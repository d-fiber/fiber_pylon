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

/// A delete that has not yet named its table.
///
/// [LocalDatabase.delete] and [StatementBatch.delete] hand one to their
/// callback, which names the table with [from] and returns the result.
///
/// ```dart
/// final removed = await LocalDatabase.delete(
///   (d) => d.from('todos').where((w) => w.isEqualTo(key: 'done', value: Value.boolean(true))),
/// );
/// ```
final class Delete {
  const Delete._();

  /// Removes rows from the table called [name].
  DeleteFrom from(String name) => DeleteFrom._(_quotedIdentifier(name));
}

/// A delete that has named its table, and is complete as it stands.
///
/// Without [where] it removes every row of the table.
final class DeleteFrom {
  DeleteFrom._(this._table, [this._where, this._whereArgs]);

  /// The name of the table to remove rows from.
  final String _table;

  /// The condition a row must meet to be removed, or `null` for every row.
  final String? _where;

  /// The values bound to the placeholders of [_where].
  final List<Value>? _whereArgs;

  /// Removes only the rows [build] matches.
  ///
  /// [build] receives an empty [FilterBuilder]. Called again, a row must meet
  /// both conditions to be removed.
  DeleteFrom where(Filter Function(FilterBuilder w) build) {
    final (clause, arguments) = _renderDatabaseFilter(build(const FilterBuilder()));
    return DeleteFrom._(_table, _bothMatch(_where, clause), [...?_whereArgs, ...arguments]);
  }
}
