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

import 'dart:io';

import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:meta/meta.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher show databaseFactory;

import '../../../../../storage/secure_storage.dart';
import 'database.dart';

/// Whether the file of the app database is encrypted.
enum EncryptionPolicy {
  /// Always: the app refuses to start on a SQLite that cannot encrypt, rather
  /// than keep its data in clear.
  required,

  /// Where SQLCipher exists — Android, iOS and macOS — and in clear elsewhere,
  /// which [AppStorage.isEncrypted] then says. The default.
  whenAvailable,

  /// Never. For a test, or a platform with no SQLCipher that must still run.
  off,
}

/// Whether the platform this app runs on has SQLCipher to encrypt with.
bool get _sqlCipherSupported => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

/// The one database the whole app shares, named after the app itself —
/// `<app name>.db` — and reachable from anywhere, as static calls, once
/// `configureSdk` has run:
///
/// ```dart
/// final key = SecureStorage.fingerprint;
/// await AppStorage.execute(key, 'CREATE TABLE IF NOT EXISTS todos (...)');
/// final id = await AppStorage.insert<Todo>(key, (i) => i.into('todos').values(todo));
/// final todos = await AppStorage.query<Todo>(key, (q) => q.from('todos').map(Todo.fromRow));
/// ```
///
/// Only the calls that talk to the database are here — the same ones
/// [LocalDatabase] has under the same names. Opening, repairing and closing
/// it are not: `configureSdk` opens it once, at launch, and it stays open for
/// as long as the app runs.
///
/// It carries no schema of its own: whoever uses it creates the tables it
/// needs with `CREATE TABLE IF NOT EXISTS`, since the file may be a fresh one
/// on any launch (see [openAppDatabase]).
@Singleton()
class AppStorage {
  AppStorage._(this._database);

  final LocalDatabase _database;

  /// Whether the app database is encrypted, by a key derived from the app's own
  /// [Fingerprint], so that a copy of the file cannot be read without it.
  ///
  /// `false` when [encryption] is [EncryptionPolicy.whenAvailable] and the
  /// platform has no SQLCipher: the data is then in clear, and this is how a
  /// project finds out.
  static bool get isEncrypted => GetIt.instance<AppStorage>()._database.isEncrypted;

  /// Whether the app database is encrypted, decided when `configureSdk` opens
  /// it: set it before that call.
  static EncryptionPolicy encryption = EncryptionPolicy.whenAvailable;

  /// Resolves the [AppStorage] `configureSdk` registers.
  ///
  /// Marked [FactoryMethod.preResolve] so `configureSdk` awaits the open — and
  /// any repair it needs — before registering the result.
  @internal
  @FactoryMethod(preResolve: true)
  static Future<AppStorage> initialize(SecureStorage secureStorage) async =>
      AppStorage._(await openAppDatabase(fingerprint: SecureStorage.fingerprint, encryption: encryption));

  /// Closes the database, which is what `GetIt.reset` does to it.
  @internal
  @disposeMethod
  Future<void> dispose() => _database.dispose();

  /// The app database, for what is inside the package: the typed tables and
  /// the tenant mechanism, which reach only what they are meant to.
  ///
  /// Not for a project. Reading the database as a whole is what the calls below
  /// are for, and they ask for the app's [Fingerprint].
  @internal
  static LocalDatabase get database => GetIt.instance<AppStorage>()._database;

  /// Declares [tables] on the app database, creating what they declare. See
  /// [LocalDatabase.declare].
  @internal
  static Future<void> declare(List<TypedTable<Object>> tables) => database.declare(tables);

  /// The database, once [fingerprint] is shown to be the app's own: reading
  /// the whole database is the whole-database mechanism, and it is closed to a
  /// caller that cannot present the fingerprint.
  static LocalDatabase _whole(Fingerprint fingerprint) {
    final db = database;
    db.wholeDatabase(fingerprint);
    return db;
  }

  /// Changes each time `configureSdk` registers a new [AppStorage], so
  /// something that prepared the database once (a table it created, say) can
  /// tell that what it prepared is no longer the one in use.
  @internal
  static Object get generation => GetIt.instance<AppStorage>();

  /// See [LocalDatabase.execute]. Like every call below, it reaches the whole
  /// database, every tenant included, and so takes the app's [Fingerprint]
  /// (`SecureStorage.fingerprint`); a [StateError] answers any other.
  static Future<void> execute(Fingerprint fingerprint, String sql, [List<Value>? arguments]) =>
      _whole(fingerprint).execute(sql, arguments);

  /// See [LocalDatabase.insert].
  static Future<int> insert<T extends Storable>(
    Fingerprint fingerprint,
    InsertValues<T> Function(Insert<T> insert) build,
  ) => _whole(fingerprint).insert<T>(build);

  /// See [LocalDatabase.query].
  static Future<List<T>> query<T extends Object>(
    Fingerprint fingerprint,
    QueryFrom<T> Function(Select<T> query) build,
  ) => _whole(fingerprint).query<T>(build);

  /// See [LocalDatabase.rawQuery].
  static Future<List<RawRow>> rawQuery(Fingerprint fingerprint, String sql, [List<Value>? arguments]) =>
      _whole(fingerprint).rawQuery(sql, arguments);

  /// See [LocalDatabase.update].
  static Future<int> update<T extends Storable>(
    Fingerprint fingerprint,
    UpdateSet<T> Function(Update<T> update) build,
  ) => _whole(fingerprint).update<T>(build);

  /// See [LocalDatabase.delete].
  static Future<int> delete(Fingerprint fingerprint, DeleteFrom Function(Delete delete) build) =>
      _whole(fingerprint).delete(build);

  /// See [LocalDatabase.transaction].
  static Future<T> transaction<T>(Fingerprint fingerprint, Future<T> Function(TransactionScope txn) action) =>
      _whole(fingerprint).transaction<T>(action);

  /// See [LocalDatabase.batch].
  static StatementBatch batch(Fingerprint fingerprint) => _whole(fingerprint).batch();

  /// See [LocalDatabase.tableExists].
  static Future<bool> tableExists(Fingerprint fingerprint, String table) => _whole(fingerprint).tableExists(table);

  /// See [LocalDatabase.tableNames].
  static Future<List<String>> tableNames(Fingerprint fingerprint) => _whole(fingerprint).tableNames();

  /// See [LocalDatabase.columns].
  static Future<List<ColumnInfo>> columns(Fingerprint fingerprint, String table) =>
      _whole(fingerprint).columns(table);

  /// See [LocalDatabase.checkpoint].
  static Future<void> checkpoint(Fingerprint fingerprint) => _whole(fingerprint).checkpoint();
}

/// The file name the app's database gets: [appName] followed by `.db`, with
/// every character a file name cannot hold replaced by `_`. An [appName] that
/// is empty once cleaned falls back to `app`.
String _fileName(String appName) {
  final cleaned = appName.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
  return '${cleaned.isEmpty ? 'app' : cleaned}.db';
}

/// Opens `<app name>.db` and hands it back healthy, whatever state the file
/// was left in:
///
/// - it does not exist yet (first launch, or deleted since the last one):
///   SQLite creates it empty;
/// - it exists and reads fine: it is used as it is, nothing is recreated;
/// - it exists but cannot be opened, or `PRAGMA quick_check` finds it
///   corrupted: it is deleted, along with its `-wal`, `-shm` and `-journal`
///   siblings, and created again — its content is lost, since there is
///   nothing left in it to read.
///
/// The app's name is read from the platform through `package_info_plus`
/// unless [appName] is given. [factory] defaults to sqflite's own
/// [databaseFactory].
///
/// This is what [AppStorage] opens itself with; it is exposed for tests only,
/// to point it at a temporary directory. Throws the [StoreError] the second
/// attempt fails with, when even a fresh file cannot be opened (a directory
/// this process may not write to, say): recreating cannot fix that.
@visibleForTesting
Future<LocalDatabase> openAppDatabase({
  String? appName,
  DatabaseFactory? factory,
  Fingerprint? fingerprint,
  EncryptionPolicy encryption = EncryptionPolicy.whenAvailable,
}) async {
  final encrypt =
      fingerprint != null &&
      (encryption == EncryptionPolicy.required ||
          (encryption == EncryptionPolicy.whenAvailable && _sqlCipherSupported));
  final resolvedFactory = factory ?? (encrypt ? cipher.databaseFactory : databaseFactory);
  final name = _fileName(appName ?? (await PackageInfo.fromPlatform()).appName);
  final path = p.join(await resolvedFactory.getDatabasesPath(), name);
  if (encrypt) _refuseClearFile(path, name);
  final db = LocalDatabase(name: name, factory: resolvedFactory, fingerprint: fingerprint, encrypt: encrypt);

  try {
    await _openHealthy(db, name);
  } on EncryptionUnavailableError {
    rethrow; // nothing is wrong with the file: deleting it would only lose it
  } on StoreError {
    await _deleteFiles(path, resolvedFactory);
    await _openHealthy(db, name);
  }
  return db;
}

/// The first bytes of every SQLite file that is not encrypted.
const _clearFileHeader = 'SQLite format 3\u0000';

/// Refuses to encrypt over a database that is in clear.
///
/// Opening it with a key would fail as if it were corrupt, and the repair
/// would then delete it: a database from before encryption existed, with the
/// data in it, would be lost silently. Delete it, or move its rows over, on
/// purpose.
void _refuseClearFile(String path, String name) {
  final file = File(path);
  if (!file.existsSync()) return;
  final header = file.openSync()..setPositionSync(0);
  try {
    final bytes = header.readSync(_clearFileHeader.length);
    if (String.fromCharCodes(bytes) == _clearFileHeader) {
      throw StateError(
        '$name is a database in clear, and the app now encrypts it. It was left as it is: '
        'delete it, or copy its rows into a new encrypted database, to go on.',
      );
    }
  } finally {
    header.closeSync();
  }
}

/// Opens [db] and runs `PRAGMA quick_check` on it, closing it again and
/// throwing [OpenFailedError] when the check finds a problem.
Future<void> _openHealthy(LocalDatabase db, String name) async {
  try {
    await db.open();
    final rows = await db.rawQuery('PRAGMA quick_check');
    final verdict = rows.isEmpty ? null : rows.first.values.first.asString;
    if (verdict != 'ok') {
      throw OpenFailedError('$name is corrupted: quick_check answered $verdict');
    }
  } catch (_) {
    await db.dispose();
    rethrow;
  }
}

Future<void> _deleteFiles(String path, DatabaseFactory factory) async {
  await factory.deleteDatabase(path);
  for (final suffix in const ['-wal', '-shm', '-journal']) {
    final sibling = File('$path$suffix');
    if (await sibling.exists()) await sibling.delete();
  }
}
