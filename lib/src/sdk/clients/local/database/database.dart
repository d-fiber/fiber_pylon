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

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'engine/app.dart' show AppStorage;
import 'engine/database.dart';
import 'engine/sort_order.dart';
import '../../environments.dart';
import '../../client.dart';
import '../local_sdk.dart';

part 'changes.dart';
part 'collection.dart';
part 'document_reference.dart';
part 'field.dart';
part 'field_value.dart';
part 'filter.dart';
part 'model.dart';
part 'order.dart';
part 'query.dart';
part 'snapshot.dart';
part 'sql.dart';
part 'tenant.dart';
part 'transaction.dart';
part 'update_builder.dart';
part 'write_batch.dart';

/// A project's own typed, document-style database, kept in the app's own
/// [AppStorage] file.
///
/// A project subclasses this and declares one [Collection] per kind of
/// document, each tied to the [Model] it stores:
///
/// ```dart
/// final class OwnDatabase extends Database {
///   final users = Collection<User>('users', User.fromJson);
///   final items = Collection<Item>('items', Item.fromJson, indexes: [Item.price_]);
/// }
///
/// await OwnDatabase().initialize(); // once, after configureSdk()
///
/// final db = Database.instance<OwnDatabase>(); // from anywhere afterwards
/// await db.users.doc('u1').set(User(id: 'u1', name: 'Ada', age: 36));
/// final adults = await db.users
///     .where((w) => w(User.age_).isGreaterThanOrEqualTo(18))
///     .orderBy((o) => [o.asc(User.name_)])
///     .get();
/// db.users.snapshots().listen((snapshot) => print(snapshot.items));
/// ```
///
/// The shape follows Firestore's own Flutter API — collections, documents,
/// queries, snapshots, batches, transactions — with everything typed on the
/// project's own models instead of `Map<String, dynamic>`, and everything
/// stored locally, one SQLite table per collection.
///
/// A [Database] is a [LocalSdkClient], so it gets [initialize], [dispose] and
/// [Database.instance] the way every pylon client does, and is `base`: a
/// project's subclass is `final` or `base` too.
///
/// Whose documents a collection holds is its own `Tunnel`'s call: each
/// [Collection] is isolated per [Tenant] by default, so two accounts on one
/// device never see each other's data, or [Tunnel.shared] when everyone should.
///
/// It only works once `configureSdk` has run, since it stores everything in
/// [AppStorage]. A write made straight through [AppStorage] instead of through
/// a [Collection] cannot tell a [Query.snapshots] listener that anything
/// changed.
abstract base class Database extends LocalSdkClient {
  /// The [T] that last reached the end of [initialize].
  ///
  /// Throws a [StateError] naming [T] when it was never initialized, or was
  /// disposed since.
  static T instance<T extends Database>() => SdkClient.instance<T>();

  @override
  Environments? get environments => null;

  /// Checks that [AppStorage] is ready and that its SQLite has the JSON
  /// functions every query here is built on, then registers this database
  /// under its own type so [Database.instance] can hand it back.
  ///
  /// Throws a [StateError] when `configureSdk` has not run yet, and one
  /// naming the missing functions when the SQLite in use lacks them — some
  /// older Android system versions do, and the fix is to open the database
  /// through a SQLite that bundles them rather than through the system's.
  @override
  Future<void> initialize() async {
    if (isInitialized) return;
    try {
      await AppStorage.database.tableNames();
    } on StateError catch (error) {
      throw StateError('$runtimeType needs configureSdk() to have run first: ${error.message}');
    }
    await _requireJsonFunctions();
    await super.initialize();
  }

  Future<void> _requireJsonFunctions() async {
    try {
      final rows = await AppStorage.database.rawQuery(
        "SELECT json_extract('{\"a\":1}', '\$.a') AS value, (SELECT count(*) FROM json_each('[1]')) AS each",
      );
      if (rows.single['value']!.asInt == 1 && rows.single['each']!.asInt == 1) return;
    } on DatabaseError {
      // falls through to the same message: a missing function is one of these
    }
    throw StateError(
      "$runtimeType needs SQLite's JSON functions (json_extract, json_each), which the SQLite in use does not "
      'have. Open the app database through a SQLite that bundles them, such as a factory from sqflite_sqlcipher '
      'or a sqlite3-based one.',
    );
  }

  /// Starts a [WriteBatch]: writes queued here, none of which touch the
  /// database until [WriteBatch.commit] applies all of them together, or none.
  WriteBatch batch() => WriteBatch._();

  /// Runs [action] as one transaction: every read and write made through the
  /// [Transaction] it is given commits together, or none of them do if
  /// [action] throws.
  ///
  /// [action] only ever reaches the database through that [Transaction] —
  /// calling a [Collection] or [DocumentReference] directly from inside it
  /// waits on the transaction it is already inside, and never returns. Unlike
  /// Firestore's own, a write applies at once rather than when [action] ends,
  /// and nothing is retried: SQLite runs one transaction at a time, so there
  /// is no conflict to retry.
  Future<R> runTransaction<R>(Future<R> Function(Transaction transaction) action) async {
    final touched = <Collection<Model>>{};
    final result = await AppStorage.database.transaction((txn) => action(Transaction._(_TransactionExecutor(txn), touched)));
    for (final collection in touched) {
      _ChangeBus.notify(collection.name);
    }
    return result;
  }
}
