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
///   ..update(db.items.doc('i1'), (u) => [u(Item.stock_).increment(-1)])
///   ..delete(db.items.doc('i2'));
/// await batch.commit();
/// ```
final class WriteBatch {
  WriteBatch._();

  final List<Future<void> Function(_Executor executor)> _operations = [];
  final Set<Collection<Model>> _collections = {};
  bool _committed = false;

  /// Queues [DocumentReference.set].
  void set<T extends Model>(DocumentReference<T> reference, T data, {bool merge = false}) =>
      _queue(reference, (executor, tenant) => reference._set(executor, tenant, data, merge));

  /// Queues [DocumentReference.update].
  void update<T extends Model>(DocumentReference<T> reference, List<FieldChange> Function(UpdateBuilder u) build) {
    final changes = _changesOf(build);
    _queue(reference, (executor, tenant) => reference._update(executor, tenant, changes));
  }

  /// Queues [DocumentReference.delete].
  void delete<T extends Model>(DocumentReference<T> reference) => _queue(reference, reference._delete);

  /// Applies every queued write in one transaction.
  ///
  /// A batch commits once: queuing into it, or committing it, afterwards
  /// throws a [StateError].
  Future<void> commit() async {
    _checkOpen();
    _committed = true;
    for (final collection in _collections) {
      await collection._ensure();
    }
    await _atomically((executor) async {
      for (final operation in _operations) {
        await operation(executor);
      }
    });
    for (final collection in _collections) {
      _ChangeBus.notify(collection.name);
    }
  }

  /// Queues [operation] on the tenant [reference] reaches right now, not the
  /// one that happens to be current when [commit] runs.
  void _queue<T extends Model>(
    DocumentReference<T> reference,
    Future<void> Function(_Executor executor, String tenant) operation,
  ) {
    _checkOpen();
    final tenant = reference._tenant;
    _collections.add(reference.parent);
    _operations.add((executor) => operation(executor, tenant));
  }

  void _checkOpen() {
    if (_committed) throw StateError('This WriteBatch was already committed.');
  }
}
