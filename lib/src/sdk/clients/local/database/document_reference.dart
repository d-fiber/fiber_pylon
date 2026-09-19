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

/// A document that never existed, or no longer does, reached by an operation
/// that needs one, such as [DocumentReference.update].
final class DocumentNotFoundError implements Exception {
  /// The document [id] of [collection] that was not found.
  const DocumentNotFoundError(this.collection, this.id);

  /// The table that was searched.
  final String collection;

  /// The key that was not there.
  final Object id;

  @override
  String toString() => 'DocumentNotFoundError(no document "$id" in "$collection")';
}

/// One document of a [Collection], which may or may not exist yet.
///
/// Holds nothing but where the document lives: [get], [set], [update],
/// [delete] and [snapshots] are what actually reach the database, on the
/// tenant that is current when each one starts.
final class DocumentReference<R extends Object, K extends Object> {
  const DocumentReference._(this.parent, this.id);

  /// The collection this document belongs to.
  final Collection<R, K> parent;

  /// This document's key in [parent].
  final K id;

  DatabaseKeyedTable<R, K> get _table => parent.table;

  /// Reads the document, which need not exist: check [DocumentSnapshot.exists].
  Future<DocumentSnapshot<R, K>> get() async => _read(_table.on(AppStorage.database));

  /// Writes [record] as this document, replacing what it held.
  ///
  /// Throws an [ArgumentError] when the record carries another key than this
  /// reference's: a document is written under its own key.
  Future<void> set(R record) => _set(_table.on(AppStorage.database), record);

  /// Changes only the columns [assignments] name, leaving the rest as they are:
  /// `users.doc('ada').update([usersTable.age.incrementBy(1), usersTable.city.to('Paris')])`.
  ///
  /// Throws a [DocumentNotFoundError] when the document does not exist.
  Future<void> update(List<DatabaseAssignment> assignments) => _update(_table.on(AppStorage.database), assignments);

  /// Removes the document. Removing one that does not exist is not an error.
  Future<void> delete() => _delete(_table.on(AppStorage.database));

  /// Reads the document now, then again after every write to it, emitting a
  /// [DocumentSnapshot] each time it differs. Nothing runs until the stream is
  /// listened to. On an isolated collection it follows [Tenant]: after
  /// [Tenant.use] it emits the new tenant's document, never the previous one's.
  Stream<DocumentSnapshot<R, K>> snapshots() =>
      _table.on(AppStorage.database).watchOne(id).map((record) => DocumentSnapshot<R, K>._(id, record));

  Future<DocumentSnapshot<R, K>> _read(DatabaseKeyedAccess<R, K> access) async =>
      DocumentSnapshot<R, K>._(id, await access.get(id));

  Future<void> _set(DatabaseKeyedAccess<R, K> access, R record) {
    final key = _table.keyOf(record);
    if (key != null && key != id) {
      throw ArgumentError.value(record, 'record', 'carries the key $key, but this document is $id');
    }
    return access.upsert(record);
  }

  Future<void> _update(DatabaseKeyedAccess<R, K> access, List<DatabaseAssignment> assignments) async {
    final changed = await access.where(_table.keyField.isEqualTo(id)).update(assignments);
    if (changed == 0) throw DocumentNotFoundError(_table.tableName, id);
  }

  Future<void> _delete(DatabaseKeyedAccess<R, K> access) => access.remove(id);

  @override
  bool operator ==(Object other) => other is DocumentReference && other.parent.table == parent.table && other.id == id;

  @override
  int get hashCode => Object.hash(parent.table, id);

  @override
  String toString() => 'DocumentReference(${_table.tableName}/$id)';
}
