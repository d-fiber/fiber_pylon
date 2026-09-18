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

enum _BatchStatement { insert, update, delete, execute, query }

/// A sequence of writes queued against a [LocalDatabase], none of which
/// touch it until [commit] or [apply] runs them. Never constructed directly;
/// [LocalDatabase.batch] hands one back.
final class DatabaseBatch {
  DatabaseBatch._(this._batch);

  final Batch _batch;
  final List<_BatchStatement> _statements = [];

  /// Queues a [LocalDatabase.insert].
  void insert<T extends DatabaseRecord>(DatabaseInsertValues<T> Function(DatabaseInsert<T> insert) build) {
    final spec = build(DatabaseInsert<T>._());
    _batch.insert(spec._table, _toNativeRow(spec._data.toRow()), conflictAlgorithm: spec._conflict);
    _statements.add(_BatchStatement.insert);
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
    _statements.add(_BatchStatement.update);
  }

  /// Queues a [LocalDatabase.delete].
  void delete(DatabaseDeleteFrom Function(DatabaseDelete delete) build) {
    final spec = build(const DatabaseDelete._());
    _batch.delete(spec._table, where: spec._where, whereArgs: _toNativeArgs(spec._whereArgs));
    _statements.add(_BatchStatement.delete);
  }

  /// Queues a [LocalDatabase.execute].
  void execute(String sql, [List<DatabaseType>? arguments]) {
    _batch.execute(sql, _toNativeArgs(arguments));
    _statements.add(_BatchStatement.execute);
  }

  /// Queues a query composed by [build] from an empty [DatabaseQuery], the
  /// same builder [LocalDatabase.query] takes.
  ///
  /// Its rows come back as a [DatabaseBatchRows] at this call's own position
  /// in the list [commit] or [apply] answers, undecoded: a batch runs every
  /// statement before it hands anything back, so [DatabaseQueryFrom.map] has
  /// nothing to map yet and is never read.
  void query(DatabaseQueryFrom<Object> Function(DatabaseQuery<Object> query) build) {
    final spec = build(DatabaseQuery<Object>._());
    _batch.query(
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
    _statements.add(_BatchStatement.query);
  }

  /// Runs every statement queued so far as one atomic unit: either they all
  /// land, or, unless [continueOnError] is `true`, none of them do.
  ///
  /// Answers one [DatabaseBatchResult] per queued statement, in the order
  /// they were queued. With [continueOnError], a statement that failed is a
  /// [DatabaseBatchFailed] at its own position rather than a throw.
  ///
  /// [noResult] skips collecting each statement's own result, worth setting
  /// for a large batch that only cares whether it succeeded. The list
  /// answered is then empty.
  Future<List<DatabaseBatchResult>> commit({bool? exclusive, bool? noResult, bool? continueOnError}) => _guarded(
    () async => _typed(await _batch.commit(exclusive: exclusive, noResult: noResult, continueOnError: continueOnError)),
  );

  /// Runs every statement queued so far without wrapping them in a
  /// transaction sqflite manages: faster, but with no all-or-nothing
  /// guarantee if one fails partway through. Prefer [commit] unless this
  /// batch is already running inside a [LocalDatabase.transaction] of its
  /// own, or another transaction not managed through this class.
  ///
  /// Answers the same list [commit] does.
  Future<List<DatabaseBatchResult>> apply({bool? noResult, bool? continueOnError}) =>
      _guarded(() async => _typed(await _batch.apply(noResult: noResult, continueOnError: continueOnError)));

  List<DatabaseBatchResult> _typed(List<Object?> results) => [
    for (var position = 0; position < results.length; position++)
      _typedResult(_statements[position], results[position]),
  ];
}

DatabaseBatchResult _typedResult(_BatchStatement statement, Object? result) {
  if (result is DatabaseException) return DatabaseBatchFailed(DatabaseError.from(result));
  return switch (statement) {
    _BatchStatement.insert => DatabaseBatchInserted(result as int?),
    _BatchStatement.update || _BatchStatement.delete => DatabaseBatchChanged(result as int),
    _BatchStatement.execute => const DatabaseBatchExecuted(),
    _BatchStatement.query => DatabaseBatchRows(
      (result as List<Object?>).cast<Map<String, Object?>>().map(_fromNativeRow).toList(),
    ),
  };
}

/// What one statement of a [DatabaseBatch] came to, at the position it was
/// queued in.
sealed class DatabaseBatchResult extends Equatable {
  const DatabaseBatchResult();
}

/// The outcome of a queued [DatabaseBatch.insert].
final class DatabaseBatchInserted extends DatabaseBatchResult {
  /// Wraps the [rowId] sqflite answered.
  const DatabaseBatchInserted(this.rowId);

  /// The row id sqflite assigned. `null` when the row was skipped, which is
  /// what [ConflictAlgorithm.ignore] does with one that collides.
  final int? rowId;

  @override
  List<Object?> get props => [rowId];
}

/// The outcome of a queued [DatabaseBatch.update] or [DatabaseBatch.delete].
final class DatabaseBatchChanged extends DatabaseBatchResult {
  /// Wraps the [count] sqflite answered.
  const DatabaseBatchChanged(this.count);

  /// How many rows the statement changed or removed.
  final int count;

  @override
  List<Object?> get props => [count];
}

/// The outcome of a queued [DatabaseBatch.execute], which answers nothing.
final class DatabaseBatchExecuted extends DatabaseBatchResult {
  /// The outcome of a statement that ran.
  const DatabaseBatchExecuted();

  @override
  List<Object?> get props => const [];
}

/// The outcome of a queued [DatabaseBatch.query].
final class DatabaseBatchRows extends DatabaseBatchResult {
  /// Wraps the [rows] the query selected.
  const DatabaseBatchRows(this.rows);

  /// The rows the query selected, undecoded.
  final List<DatabaseRow> rows;

  @override
  List<Object?> get props => [rows];
}

/// The outcome of a queued statement that failed under `continueOnError`.
final class DatabaseBatchFailed extends DatabaseBatchResult {
  /// Wraps the [error] the statement raised.
  const DatabaseBatchFailed(this.error);

  /// Why the statement failed, read the way every other method here reads a
  /// sqflite failure.
  final DatabaseError error;

  @override
  List<Object?> get props => [error];
}
