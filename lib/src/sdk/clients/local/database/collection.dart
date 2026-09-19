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

/// Every document of one kind: the rows of one table, and the [Query] that
/// matches all of them, so everything a [Query] offers is available on it
/// directly.
///
/// Declared once, as a field of a project's own [Database], over the table
/// that describes it:
///
/// ```dart
/// final usersTable = UsersTable();
/// late final users = Collection(usersTable);
/// ```
///
/// Whose documents it holds is its table's `tunnel`: the current [Tenant]'s
/// only, on an isolated table, or everyone's on a shared one.
final class Collection<R extends Object, K extends Object> extends Query<R, K> {
  /// The collection of the records [table] holds.
  Collection(super._table) : super._();

  /// The table this collection is on: its columns are what a query is written
  /// with, and what [Database.initialize] declares.
  KeyedTable<R, K> get table => _table;

  /// The document [id] of this collection.
  ///
  /// Reads and writes nothing until asked to: the document need not exist.
  DocumentReference<R, K> doc(K id) => DocumentReference._(this, id);

  /// Stores [record] as a new document and answers its reference, under the key
  /// the record carries — or the one the engine assigns when it carries none.
  ///
  /// Throws a `UniqueConstraintError` when a document already has that
  /// key: use [DocumentReference.set] to overwrite one.
  Future<DocumentReference<R, K>> add(R record) async {
    final saved = await _table.on(AppStorage.database).insert(record);
    return doc(_table.keyOf(saved) ?? (throw StateError('${_table.tableName} kept a record with no key.')));
  }

  /// Removes every document of the current tenant, keeping the table.
  Future<void> clear() => _table.on(AppStorage.database).deleteAll();

  /// This collection across every tenant: the whole-database mechanism, opened
  /// only by the app's [Fingerprint]. It reads, and edits or removes what a
  /// filter keeps; see [WholeRows].
  WholeRows<R> onWholeDatabase(Fingerprint fingerprint) =>
      _table.onWholeDatabase(AppStorage.database, fingerprint);
}
