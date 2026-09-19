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

import '../../../../storage/secure_storage.dart' show Fingerprint;
import '../../client.dart';
import '../../environments.dart';
import '../local_sdk.dart';
import 'engine/app.dart' show AppStorage;
import 'engine/database.dart';

part 'collection.dart';
part 'document_reference.dart';
part 'query.dart';
part 'snapshot.dart';
part 'write_batch.dart';

/// A project's own database: the collections it declares, each on a table the
/// engine creates and keeps in the app's own database file.
///
/// A project declares one table per kind of record, the way `LocalDatabase`
/// documents it, and one [Collection] over each:
///
/// ```dart
/// final class OwnDatabase extends Database {
///   final usersTable = UsersTable();
///   late final users = Collection(usersTable);
///
///   @override
///   List<Collection<Object, Object>> get collections => [users];
/// }
///
/// await OwnDatabase().initialize(); // once, after configureSdk()
///
/// final db = Database.instance<OwnDatabase>(); // from anywhere afterwards
/// await db.users.doc('ada').set(const User(id: 'ada', name: 'Ada', age: 36));
/// final adults = await db.users
///     .where(db.usersTable.age.isGreaterThanOrEqualTo(18))
///     .orderBy([db.usersTable.name.asc()])
///     .get();
/// db.users.snapshots().listen((snapshot) => print(snapshot.items));
/// ```
///
/// The vocabulary is Firestore's — collections, documents, queries, snapshots,
/// batches, transactions — over typed tables: a filter, an order or an update
/// is written with the table's own columns, so a misspelled name or a value of
/// the wrong type does not compile. There is no query language of its own here:
/// everything is the engine's.
///
/// Whose rows a collection holds is its table's tunnel: isolated per [Tenant] by
/// default for a table that says so, so that two accounts on one device never
/// see each other's data, or shared. Reading the whole database is another
/// mechanism, opened only by the app's [Fingerprint].
///
/// A [Database] is a [LocalSdkClient], so it gets [initialize], [dispose] and
/// [Database.instance] the way every pylon client does, and is `base`: a
/// project's subclass is `final` or `base` too. It needs `configureSdk` to have
/// run, since it lives in [AppStorage].
abstract base class Database extends LocalSdkClient {
  /// The [T] that last reached the end of [initialize].
  ///
  /// Throws a [StateError] naming [T] when it was never initialized, or was
  /// disposed since.
  static T instance<T extends Database>() => SdkClient.instance<T>();

  @override
  Environments? get environments => null;

  /// Every collection this database has, which [initialize] declares — the
  /// tables are created, and what a table gained since the file was written is
  /// added — before anything is registered.
  ///
  /// A collection missing from this list has no table: reading it fails.
  List<Collection<Object, Object>> get collections;

  /// Checks that [AppStorage] is ready, declares the tables of [collections],
  /// then registers this database under its own type so [Database.instance] can
  /// hand it back.
  ///
  /// Throws a [StateError] when `configureSdk` has not run yet, and the
  /// engine's own error when a table cannot be declared.
  @override
  Future<void> initialize() async {
    if (isInitialized) return;
    try {
      AppStorage.database;
    } on StateError catch (error) {
      throw StateError('$runtimeType needs configureSdk() to have run first: ${error.message}');
    }
    await AppStorage.declare([for (final collection in collections) collection.table]);
    await super.initialize();
  }

  /// Starts a [WriteBatch]: writes queued here, none of which touch the
  /// database until [WriteBatch.commit] applies all of them together, or none.
  WriteBatch batch() => WriteBatch._();

  /// Runs [action] as one transaction: every read and write made through the
  /// [Transaction] it is given commits together, or none of them do if
  /// [action] throws.
  ///
  /// It runs on the tenant that was current when it began, however long it
  /// takes. [action] only ever reaches the database through that
  /// [Transaction]: calling a collection directly from inside it waits on the
  /// transaction it is already inside, and never returns. Nothing is retried:
  /// SQLite runs one transaction at a time, so there is no conflict to retry.
  Future<R> runTransaction<R>(Future<R> Function(Transaction transaction) action) {
    final tenant = Tenant.current;
    return AppStorage.database.transaction((txn) => action(Transaction._(txn, tenant)));
  }

  /// Moves every anonymous row — what was saved before anyone signed in — to
  /// the current [Tenant], in every isolated table, and answers how many moved.
  /// See [LocalDatabaseTenants.adoptAnonymousRows].
  Future<int> adoptAnonymousRows({TransferConflict onConflict = TransferConflict.keepTarget}) =>
      AppStorage.database.adoptAnonymousRows(onConflict: onConflict);

  /// Removes every row of the current [Tenant], in every isolated table: the
  /// account is deleted. See [LocalDatabaseTenants.purgeCurrentTenant].
  Future<void> purgeCurrentTenant() => AppStorage.database.purgeCurrentTenant();

  /// The whole-database mechanism: listing the tenants, removing one's rows,
  /// moving rows from one tenant to another. Opened only by the app's
  /// [Fingerprint]; a [StateError] answers any other.
  DatabaseWholeAccess wholeDatabase(Fingerprint fingerprint) => AppStorage.database.wholeDatabase(fingerprint);
}
