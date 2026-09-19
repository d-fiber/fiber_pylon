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

/// The reads and writes of one [Database.runTransaction].
///
/// Every call below runs inside that transaction, so a read sees the writes
/// made before it, and all of them commit together or not at all. Each call
/// must be awaited before the next starts.
final class Transaction {
  Transaction._(this._executor, this._touched);

  final _Executor _executor;
  final Set<Collection<Model>> _touched;

  /// Reads [reference], which need not exist.
  Future<DocumentSnapshot<T>> get<T extends Model>(DocumentReference<T> reference) async {
    final tenant = reference._tenant;
    await reference.parent._createTable(_executor);
    return reference._read(_executor, tenant);
  }

  /// Does what [DocumentReference.set] does, inside this transaction.
  Future<void> set<T extends Model>(DocumentReference<T> reference, T data, {bool merge = false}) =>
      _write(reference, (executor, tenant) => reference._set(executor, tenant, data, merge));

  /// Does what [DocumentReference.update] does, inside this transaction.
  Future<void> update<T extends Model>(
    DocumentReference<T> reference,
    List<FieldChange> Function(UpdateBuilder u) build,
  ) {
    final changes = _changesOf(build);
    return _write(reference, (executor, tenant) => reference._update(executor, tenant, changes));
  }

  /// Does what [DocumentReference.delete] does, inside this transaction.
  Future<void> delete<T extends Model>(DocumentReference<T> reference) => _write(reference, reference._delete);

  Future<void> _write<T extends Model>(
    DocumentReference<T> reference,
    Future<void> Function(_Executor executor, String tenant) operation,
  ) async {
    final tenant = reference._tenant;
    await reference.parent._createTable(_executor);
    _touched.add(reference.parent);
    await operation(_executor, tenant);
  }
}
