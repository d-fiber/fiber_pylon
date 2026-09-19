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

/// A row named by its key that a table does not hold, reached by a write that
/// needs one, such as [Batch.update].
final class RowNotFoundError implements Exception {
  /// The row [key] of [table] that was not found.
  const RowNotFoundError(this.table, this.key);

  /// The table that was searched.
  final String table;

  /// The key that was not there.
  final Object key;

  @override
  String toString() => 'RowNotFoundError(no row "$key" in "$table")';
}

/// Writes queued together and applied all at once: every one lands, or, if any
/// fails, none does. Started with [Database.batch].
///
/// ```dart
/// final batch = db.batch()
///   ..upsert(db.users, user)
///   ..update(db.items, 'i1', [db.items.stock.incrementBy(-1)])
///   ..remove(db.items, 'i2');
/// await batch.commit();
/// ```
///
/// It commits on the tenant that was current when [commit] began.
final class Batch {
  Batch._();

  final List<Future<void> Function(Connection session, String? tenant)> _operations = [];
  bool _committed = false;

  /// Queues an insert of [record] into [table].
  void insert<R extends Object, K extends Object>(KeyedTable<R, K> table, R record) => _queue((session, tenant) async {
    await table.onHeldTenant(session, tenant).insert(record);
  });

  /// Queues an upsert of [record] into [table]: it replaces the row that holds
  /// its key, or is inserted when none does.
  void upsert<R extends Object, K extends Object>(KeyedTable<R, K> table, R record) => _queue((session, tenant) async {
    await table.onHeldTenant(session, tenant).upsert(record);
  });

  /// Queues a change of the columns [assignments] name on the row of [table]
  /// held under [key], leaving the rest as they are.
  ///
  /// Throws a [RowNotFoundError] when [commit] runs and no row holds [key],
  /// and nothing is applied.
  void update<R extends Object, K extends Object>(KeyedTable<R, K> table, K key, List<Assignment> assignments) =>
      _queue((session, tenant) async {
        final changed = await table
            .onHeldTenant(session, tenant)
            .where(table.keyField.isEqualTo(key))
            .update(assignments);
        if (changed == 0) throw RowNotFoundError(table.tableName, key);
      });

  /// Queues the removal of the row of [table] held under [key]. Removing one
  /// that does not exist is not an error.
  void remove<R extends Object, K extends Object>(KeyedTable<R, K> table, K key) => _queue((session, tenant) async {
    await table.onHeldTenant(session, tenant).remove(key);
  });

  /// Applies every queued write in one transaction.
  ///
  /// A batch commits once: queuing into it, or committing it, afterwards throws
  /// a [StateError].
  Future<void> commit() {
    _checkOpen();
    _committed = true;
    final tenant = Tenant.current;
    return LocalDatabase.instance.runTransaction((txn) async {
      for (final operation in _operations) {
        await operation(txn, tenant);
      }
    });
  }

  void _queue(Future<void> Function(Connection session, String? tenant) operation) {
    _checkOpen();
    _operations.add(operation);
  }

  void _checkOpen() {
    if (_committed) throw StateError('This Batch was already committed.');
  }
}

/// The reads and writes of one [Database.runTransaction].
///
/// Every statement run through [from] happens inside that transaction, so a read
/// sees the writes made before it, and all of them commit together or not at
/// all. Each call must be awaited before the next starts.
final class Transaction {
  Transaction._(this._session, this._tenant);

  final Connection _session;
  final String? _tenant;

  /// The rows of [table], inside this transaction, on the tenant that was
  /// current when it began. The same statements [Database.from] offers.
  KeyedAccess<R, K> from<R extends Object, K extends Object>(KeyedTable<R, K> table) =>
      table.onHeldTenant(_session, _tenant);
}
