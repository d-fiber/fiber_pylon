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

/// A sequence of writes queued against a [LocalDatabase], none of which
/// touch it until [commit] or [apply] runs them. Never constructed directly;
/// [LocalDatabase.batch] hands one back.
final class DatabaseBatch {
  DatabaseBatch._(this._batch);

  final Batch _batch;

  /// Queues a [LocalDatabase.insert].
  void insert<T extends DatabaseRecord>(DatabaseInsertValues<T> Function(DatabaseInsert<T> insert) build) {
    final spec = build(DatabaseInsert<T>._());
    _batch.insert(spec._table, _toNativeRow(spec._data.toRow()), conflictAlgorithm: spec._conflict);
  }

  /// Queues a [LocalDatabase.update].
  void update<T extends DatabaseRecord>(DatabaseUpdateSet<T> Function(DatabaseUpdate<T> update) build) {
    final spec = build(DatabaseUpdate<T>._());
    _batch.update(
      spec._table,
      _toNativeRow(spec._data.toRow()),
      where: spec._where,
      whereArgs: _toNativeArgs(spec._whereArgs),
      conflictAlgorithm: spec._conflict,
    );
  }

  /// Queues a [LocalDatabase.delete].
  void delete(DatabaseDeleteFrom Function(DatabaseDelete delete) build) {
    final spec = build(const DatabaseDelete._());
    _batch.delete(spec._table, where: spec._where, whereArgs: _toNativeArgs(spec._whereArgs));
  }

  /// Queues a [LocalDatabase.execute].
  void execute(String sql, [List<SqlValue>? arguments]) => _batch.execute(sql, _toNativeArgs(arguments));

  /// Queues a [LocalDatabase.query]. Its rows land at this call's own
  /// position in [commit]'s or [apply]'s result list, as a raw
  /// `List<Map<String, Object?>>` — sqflite's own batch API answers every
  /// queued statement through one shared, loosely typed result list, so
  /// this is the one place [DatabaseBatch] cannot hand back a [DatabaseRow] the
  /// way every other method here does; decode it with
  /// [SqlValue.fromNative] per column.
  void query(
    String table, {
    bool distinct = false,
    List<String>? columns,
    String? where,
    List<SqlValue>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => _batch.query(
    table,
    distinct: distinct,
    columns: columns,
    where: where,
    whereArgs: _toNativeArgs(whereArgs),
    groupBy: groupBy,
    having: having,
    orderBy: orderBy,
    limit: limit,
    offset: offset,
  );

  /// Runs every statement queued so far as one atomic unit: either they all
  /// land, or — unless [continueOnError] is `true` — none of them do.
  ///
  /// [noResult] skips collecting each statement's own result (an inserted
  /// row id, an affected-row count, a query's rows), worth setting for a
  /// large batch that only cares whether it succeeded.
  Future<List<Object?>> commit({bool? exclusive, bool? noResult, bool? continueOnError}) =>
      _guarded(() => _batch.commit(exclusive: exclusive, noResult: noResult, continueOnError: continueOnError));

  /// Runs every statement queued so far without wrapping them in a
  /// transaction sqflite manages — faster, but with no all-or-nothing
  /// guarantee if one fails partway through. Prefer [commit] unless this
  /// batch is already running inside a [LocalDatabase.transaction] of its
  /// own, or another transaction not managed through this class.
  Future<List<Object?>> apply({bool? noResult, bool? continueOnError}) =>
      _guarded(() => _batch.apply(noResult: noResult, continueOnError: continueOnError));
}
