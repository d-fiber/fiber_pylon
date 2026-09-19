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
import 'engine/database.dart';

part 'batch.dart';

/// A project's own database: the tables it declares, which the engine creates
/// and keeps in the app's own database file, and the statements it runs on them.
///
/// A project declares one [KeyedTable] per kind of record, lists them in
/// [tables], and reaches each one with [from]:
///
/// ```dart
/// final class OwnDatabase extends Database {
///   final users = UsersTable();
///
///   @override
///   List<KeyedTable<Object, Object>> get tables => [users];
/// }
///
/// await OwnDatabase().initialize(); // once, after configureSdk()
///
/// final db = Database.instance<OwnDatabase>(); // from anywhere afterwards
/// await db.from(db.users).insert(const User(id: 'ada', name: 'Ada', age: 36));
/// final adults = await db
///     .from(db.users)
///     .where(db.users.age.isGreaterThanOrEqualTo(18))
///     .orderBy([db.users.name.asc()])
///     .limit(20)
///     .select();
/// db.from(db.users).watch().listen(print);
/// ```
///
/// The vocabulary is SQL's: `from`, `where`, `orderBy`, `limit`, `offset`,
/// `select`, `insert`, `upsert`, `update`, `delete`, `count`, `exists`. A filter,
/// an order or an update is written with the table's own columns, so a
/// misspelled name or a value of the wrong type does not compile.
///
/// Whose rows a table holds is its `tunnel`: isolated per [Tenant] by default
/// for a table that says so, so that two accounts on one device never see each
/// other's data, or shared. Reading the whole database is another mechanism,
/// opened only by the app's [Fingerprint].
///
/// A [Database] is a [LocalSdkClient], so it gets [initialize], [dispose] and
/// [Database.instance] the way every pylon client does, and is `base`: a
/// project's subclass is `final` or `base` too. It needs `configureSdk` to have
/// run, since it lives in [LocalDatabase].
abstract base class Database extends LocalSdkClient {
  /// The [T] that last reached the end of [initialize].
  ///
  /// Throws a [StateError] naming [T] when it was never initialized, or was
  /// disposed since.
  static T instance<T extends Database>() => SdkClient.instance<T>();

  @override
  Environments? get environments => null;

  /// Every table this database has, which [initialize] declares: the tables are
  /// created, and what a table gained since the file was written is added,
  /// before anything is registered.
  ///
  /// A table missing from this list does not exist: reading it fails.
  List<KeyedTable<Object, Object>> get tables;

  /// Checks that [LocalDatabase] is ready, declares the [tables], then
  /// registers this database under its own type so [Database.instance] can hand
  /// it back.
  ///
  /// Throws a [StateError] when `configureSdk` has not run yet, and the
  /// engine's own error when a table cannot be declared.
  @override
  Future<void> initialize() async {
    if (isInitialized) return;
    try {
      LocalDatabase.instance;
    } on StateError catch (error) {
      throw StateError('$runtimeType needs configureSdk() to have run first: ${error.message}');
    }
    await LocalDatabase.declare(tables);
    await super.initialize();
  }

  /// The rows of [table], to read with `where`, `orderBy`, `limit`, `offset` and
  /// `select`, or to write with `insert`, `upsert`, `update`, `delete`, `get`
  /// and `remove`.
  ///
  /// Reads and writes nothing until a statement is run, and answers the current
  /// [Tenant]'s rows only, on an isolated table.
  ///
  /// Throws a [StateError] when [table] is not one of the [tables] this
  /// database declares.
  KeyedAccess<R, K> from<R extends Object, K extends Object>(KeyedTable<R, K> table) =>
      table.on(LocalDatabase.instance);

  /// [table] across every tenant: the whole-database mechanism, opened only by
  /// the app's [Fingerprint]. It reads, and edits or removes what a filter
  /// keeps; see [WholeRows].
  WholeRows<R> fromWholeDatabase<R extends Object>(TypedTable<R> table, Fingerprint fingerprint) =>
      table.onWholeDatabase(LocalDatabase.instance, fingerprint);

  /// Starts a [Batch]: writes queued here, none of which touch the database
  /// until [Batch.commit] applies all of them together, or none.
  Batch batch() => Batch._();

  /// Runs [action] as one transaction: every read and write made through the
  /// [Transaction] it is given commits together, or none of them do if
  /// [action] throws.
  ///
  /// It runs on the tenant that was current when it began, however long it
  /// takes. [action] only ever reaches the database through that
  /// [Transaction]: calling [from] on the database from inside it waits on the
  /// transaction it is already inside, and never returns. Nothing is retried:
  /// SQLite runs one transaction at a time, so there is no conflict to retry.
  Future<R> runTransaction<R>(Future<R> Function(Transaction transaction) action) {
    final tenant = Tenant.current;
    return LocalDatabase.instance.runTransaction((txn) => action(Transaction._(txn, tenant)));
  }

  /// Moves every anonymous row (what was saved before anyone signed in) to the
  /// current [Tenant], in every isolated table, and answers how many moved.
  /// See [LocalDatabaseTenants.adoptAnonymousRows].
  Future<int> adoptAnonymousRows({TransferConflict onConflict = TransferConflict.keepTarget}) =>
      LocalDatabase.instance.adoptAnonymousRows(onConflict: onConflict);

  /// Removes every row of the current [Tenant], in every isolated table: the
  /// account is deleted. See [LocalDatabaseTenants.purgeCurrentTenant].
  Future<void> purgeCurrentTenant() => LocalDatabase.instance.purgeCurrentTenant();

  /// The whole-database mechanism: listing the tenants, removing one's rows,
  /// moving rows from one tenant to another. Opened only by the app's
  /// [Fingerprint]; a [StateError] answers any other.
  WholeAccess wholeDatabase(Fingerprint fingerprint) => LocalDatabase.instance.wholeDatabase(fingerprint);
}
