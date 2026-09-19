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

enum _BatchStatement { insert, update, delete, execute, query }

/// A sequence of statements queued against a [LocalDatabase], none of which
/// runs until [commit] or [apply] does.
///
/// [LocalDatabase.batch] gives one. A statement queued here answers nothing
/// itself: its outcome is a [BatchResult] at the position it was queued in,
/// in the list [commit] or [apply] answers.
///
/// A batch is much faster than an insert, update or delete per row in a loop,
/// since each of those commits on its own.
final class StatementBatch {
  StatementBatch._(this._executor, this._owner) : _batch = _executor.batch();

  /// Where the queued statements run: the database, or the transaction this
  /// batch was made inside.
  final DatabaseExecutor _executor;

  /// The database this batch was made from, which its writes are announced on.
  final LocalDatabase _owner;

  /// The statements queued since the last [commit] or [apply].
  Batch _batch;

  /// The kind of each statement in [_batch], in queue order.
  List<_BatchStatement> _statements = [];

  /// Queues an insert composed by [build], as [LocalDatabase.insert] takes it.
  ///
  /// Its outcome is a [BatchInserted].
  void insert<T extends Storable>(InsertValues<T> Function(Insert<T> insert) build) {
    final spec = build(Insert<T>._());
    _batch.rawInsert(spec._sql, spec._arguments);
    _statements.add(_BatchStatement.insert);
  }

  /// Queues an update composed by [build], as [LocalDatabase.update] takes it.
  ///
  /// Its outcome is a [BatchChanged].
  void update<T extends Storable>(UpdateSet<T> Function(Update<T> update) build) {
    final spec = build(Update<T>._());
    _batch.update(
      spec._table,
      _toNativeRow(spec._data.toRow()),
      where: spec._where,
      whereArgs: _toNativeArgs(spec._whereArgs),
      conflictAlgorithm: spec._conflict,
    );
    _statements.add(_BatchStatement.update);
  }

  /// Queues a delete composed by [build], as [LocalDatabase.delete] takes it.
  ///
  /// Its outcome is a [BatchChanged].
  void delete(DeleteFrom Function(Delete delete) build) {
    final spec = build(const Delete._());
    _batch.delete(spec._table, where: spec._where, whereArgs: _toNativeArgs(spec._whereArgs));
    _statements.add(_BatchStatement.delete);
  }

  /// Queues the SQL [sql], each `?` in it bound to the next of [arguments], as
  /// [LocalDatabase.execute] runs it.
  ///
  /// Its outcome is a [BatchExecuted].
  void execute(String sql, [List<Value>? arguments]) {
    _batch.execute(sql, _toNativeArgs(arguments));
    _statements.add(_BatchStatement.execute);
  }

  /// Queues a query composed by [build], as [LocalDatabase.query] takes it.
  ///
  /// Its outcome is a [BatchRows], undecoded: the rows come back once the whole
  /// batch has run, so [QueryFrom.map] is never read.
  void query(QueryFrom<Object> Function(Select<Object> query) build) {
    final spec = build(Select<Object>._());
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

  /// Runs every statement queued so far as one unit: they all take effect, or,
  /// when one fails, none does.
  ///
  /// The answer holds one [BatchResult] per statement, in the order they were
  /// queued. With [continueOnError], a statement that fails does not stop the
  /// others and is a [BatchFailed] at its own position instead of a throw, and
  /// the statements that succeeded stay.
  ///
  /// With [noResult] the answer is empty, which spares a large batch that only
  /// cares whether it succeeded from collecting every outcome.
  ///
  /// Whether it succeeds or not, this batch is empty afterwards, so a statement
  /// never runs twice. To retry a batch that failed, queue its statements
  /// again.
  ///
  /// Inside a [LocalDatabase.transaction] the statements take effect with that
  /// transaction, not with this call, and setting [exclusive] throws an
  /// [ArgumentError].
  Future<List<BatchResult>> commit({bool? exclusive, bool? noResult, bool? continueOnError}) =>
      _run((batch) => batch.commit(exclusive: exclusive, noResult: noResult, continueOnError: continueOnError));

  /// Runs every statement queued so far without making them one unit, so
  /// statements that ran before a failure stay.
  ///
  /// Prefer [commit], which does the same inside a [LocalDatabase.transaction]
  /// and otherwise keeps the statements all-or-nothing. The answer is the list
  /// [commit] gives, and this batch is empty afterwards the same way.
  Future<List<BatchResult>> apply({bool? noResult, bool? continueOnError}) =>
      _run((batch) => batch.apply(noResult: noResult, continueOnError: continueOnError));

  /// Runs [execute] on the statements queued so far and answers their typed
  /// outcomes.
  ///
  /// A batch may hold raw SQL, so it cannot say which tables it changed and
  /// every watcher is told, even when it only queried.
  Future<List<BatchResult>> _run(Future<List<Object?>> Function(Batch batch) execute) {
    final batch = _batch;
    final statements = _statements;
    _batch = _executor.batch();
    _statements = [];
    return _guarded(() async {
      final results = _typed(statements, await execute(batch));
      _owner._notifyWrite(null);
      return results;
    });
  }

  List<BatchResult> _typed(List<_BatchStatement> statements, List<Object?> results) => [
    for (var position = 0; position < results.length; position++) _typedResult(statements[position], results[position]),
  ];
}

BatchResult _typedResult(_BatchStatement statement, Object? result) {
  if (result is DatabaseException) return BatchFailed(StoreError.from(result));
  return switch (statement) {
    _BatchStatement.insert => BatchInserted(result as int?),
    _BatchStatement.update || _BatchStatement.delete => BatchChanged(result as int),
    _BatchStatement.execute => const BatchExecuted(),
    _BatchStatement.query => BatchRows(
      (result as List<Object?>).cast<Map<String, Object?>>().map(_fromNativeRow).toList(),
    ),
  };
}

/// What one statement of a [StatementBatch] came to, at the position it was
/// queued in.
///
/// A `switch` over a [BatchResult] is exhaustive with [BatchInserted],
/// [BatchChanged], [BatchExecuted], [BatchRows] and [BatchFailed].
sealed class BatchResult extends Equatable {
  const BatchResult();
}

/// The outcome of a queued [StatementBatch.insert].
final class BatchInserted extends BatchResult {
  /// The outcome of an insert that assigned [rowId].
  const BatchInserted(this.rowId);

  /// The row id the database assigned to the inserted row.
  ///
  /// `null` when the row was skipped, which is what [ConflictAlgorithm.ignore]
  /// does with one that collides.
  final int? rowId;

  @override
  List<Object?> get props => [rowId];
}

/// The outcome of a queued [StatementBatch.update] or [StatementBatch.delete].
final class BatchChanged extends BatchResult {
  /// The outcome of a statement that changed [count] rows.
  const BatchChanged(this.count);

  /// How many rows the statement changed or removed.
  final int count;

  @override
  List<Object?> get props => [count];
}

/// The outcome of a queued [StatementBatch.execute], which answers nothing.
final class BatchExecuted extends BatchResult {
  /// The outcome of an executed statement.
  const BatchExecuted();

  @override
  List<Object?> get props => const [];
}

/// The outcome of a queued [StatementBatch.query].
final class BatchRows extends BatchResult {
  /// The outcome of a query that selected [rows].
  const BatchRows(this.rows);

  /// The rows the query selected, undecoded.
  final List<RawRow> rows;

  @override
  List<Object?> get props => [rows];
}

/// The outcome of a queued statement that failed under `continueOnError`.
final class BatchFailed extends BatchResult {
  /// The outcome of a statement that failed with [error].
  const BatchFailed(this.error);

  /// Why the statement failed.
  final StoreError error;

  @override
  List<Object?> get props => [error];
}
