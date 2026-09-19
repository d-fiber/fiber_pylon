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

/// Writes queued together and applied all at once: every one lands, or — if
/// any fails — none does. Started with [Database.batch].
///
/// ```dart
/// final batch = db.batch()
///   ..set(db.users.doc('u1'), user)
///   ..update(db.items.doc('i1'), [db.itemsTable.stock.incrementBy(-1)])
///   ..delete(db.items.doc('i2'));
/// await batch.commit();
/// ```
///
/// It commits on the tenant that was current when [commit] began.
final class WriteBatch {
  WriteBatch._();

  final List<Future<void> Function(Connection session, String? tenant)> _operations = [];
  bool _committed = false;

  /// Queues [DocumentReference.set].
  void set<R extends Object, K extends Object>(DocumentReference<R, K> reference, R record) =>
      _queue((session, tenant) => reference._set(reference._table.onHeldTenant(session, tenant), record));

  /// Queues [DocumentReference.update].
  void update<R extends Object, K extends Object>(
    DocumentReference<R, K> reference,
    List<Assignment> assignments,
  ) => _queue((session, tenant) => reference._update(reference._table.onHeldTenant(session, tenant), assignments));

  /// Queues [DocumentReference.delete].
  void delete<R extends Object, K extends Object>(DocumentReference<R, K> reference) =>
      _queue((session, tenant) => reference._delete(reference._table.onHeldTenant(session, tenant)));

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
    if (_committed) throw StateError('This WriteBatch was already committed.');
  }
}

/// The reads and writes of one [Database.runTransaction].
///
/// Every call below runs inside that transaction, so a read sees the writes
/// made before it, and all of them commit together or not at all. Each call
/// must be awaited before the next starts.
final class Transaction {
  Transaction._(this._session, this._tenant);

  final Connection _session;
  final String? _tenant;

  KeyedAccess<R, K> _access<R extends Object, K extends Object>(DocumentReference<R, K> reference) =>
      reference._table.onHeldTenant(_session, _tenant);

  /// Reads [reference], which need not exist.
  Future<DocumentSnapshot<R, K>> get<R extends Object, K extends Object>(DocumentReference<R, K> reference) =>
      reference._read(_access(reference));

  /// Does what [DocumentReference.set] does, inside this transaction.
  Future<void> set<R extends Object, K extends Object>(DocumentReference<R, K> reference, R record) =>
      reference._set(_access(reference), record);

  /// Does what [DocumentReference.update] does, inside this transaction.
  Future<void> update<R extends Object, K extends Object>(
    DocumentReference<R, K> reference,
    List<Assignment> assignments,
  ) => reference._update(_access(reference), assignments);

  /// Does what [DocumentReference.delete] does, inside this transaction.
  Future<void> delete<R extends Object, K extends Object>(DocumentReference<R, K> reference) =>
      reference._delete(_access(reference));
}
