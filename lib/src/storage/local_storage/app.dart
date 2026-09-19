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

import 'database.dart';

/// The one database the whole app shares, named after the app itself —
/// `<app name>.db` — and reachable from anywhere, as static calls, once
/// `configureSdk` has run:
///
/// ```dart
/// await AppStorage.execute('CREATE TABLE IF NOT EXISTS todos (...)');
/// final id = await AppStorage.insert<Todo>((i) => i.into('todos').values(todo));
/// final todos = await AppStorage.query<Todo>((q) => q.from('todos').map(Todo.fromRow));
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

  /// Resolves the [AppStorage] `configureSdk` registers.
  ///
  /// Marked [FactoryMethod.preResolve] so `configureSdk` awaits the open — and
  /// any repair it needs — before registering the result.
  @internal
  @FactoryMethod(preResolve: true)
  static Future<AppStorage> initialize() async => AppStorage._(await openAppDatabase());

  /// Closes the database, which is what `GetIt.reset` does to it.
  @internal
  @disposeMethod
  Future<void> dispose() => _database.dispose();

  static LocalDatabase get _db => GetIt.instance<AppStorage>()._database;

  /// Changes each time `configureSdk` registers a new [AppStorage], so
  /// something that prepared the database once (a table it created, say) can
  /// tell that what it prepared is no longer the one in use.
  @internal
  static Object get generation => GetIt.instance<AppStorage>();

  /// See [LocalDatabase.execute].
  static Future<void> execute(String sql, [List<DatabaseType>? arguments]) => _db.execute(sql, arguments);

  /// See [LocalDatabase.insert].
  static Future<int> insert<T extends DatabaseRecord>(
    DatabaseInsertValues<T> Function(DatabaseInsert<T> insert) build,
  ) => _db.insert<T>(build);

  /// See [LocalDatabase.query].
  static Future<List<T>> query<T extends Object>(DatabaseQueryFrom<T> Function(DatabaseQuery<T> query) build) =>
      _db.query<T>(build);

  /// See [LocalDatabase.rawQuery].
  static Future<List<DatabaseRow>> rawQuery(String sql, [List<DatabaseType>? arguments]) =>
      _db.rawQuery(sql, arguments);

  /// See [LocalDatabase.update].
  static Future<int> update<T extends DatabaseRecord>(DatabaseUpdateSet<T> Function(DatabaseUpdate<T> update) build) =>
      _db.update<T>(build);

  /// See [LocalDatabase.delete].
  static Future<int> delete(DatabaseDeleteFrom Function(DatabaseDelete delete) build) => _db.delete(build);

  /// See [LocalDatabase.transaction].
  static Future<T> transaction<T>(Future<T> Function(DatabaseTransaction txn) action) => _db.transaction<T>(action);

  /// See [LocalDatabase.batch].
  static DatabaseBatch batch() => _db.batch();

  /// See [LocalDatabase.tableExists].
  static Future<bool> tableExists(String table) => _db.tableExists(table);

  /// See [LocalDatabase.tableNames].
  static Future<List<String>> tableNames() => _db.tableNames();

  /// See [LocalDatabase.columns].
  static Future<List<DatabaseColumn>> columns(String table) => _db.columns(table);

  /// See [LocalDatabase.checkpoint].
  static Future<void> checkpoint() => _db.checkpoint();
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
/// to point it at a temporary directory. Throws the [DatabaseError] the second
/// attempt fails with, when even a fresh file cannot be opened (a directory
/// this process may not write to, say): recreating cannot fix that.
@visibleForTesting
Future<LocalDatabase> openAppDatabase({String? appName, DatabaseFactory? factory}) async {
  final resolvedFactory = factory ?? databaseFactory;
  final name = _fileName(appName ?? (await PackageInfo.fromPlatform()).appName);
  final path = p.join(await resolvedFactory.getDatabasesPath(), name);
  final db = LocalDatabase(name: name, factory: resolvedFactory);

  try {
    await _openHealthy(db, name);
  } on DatabaseError {
    await _deleteFiles(path, resolvedFactory);
    await _openHealthy(db, name);
  }
  return db;
}

/// Opens [db] and runs `PRAGMA quick_check` on it, closing it again and
/// throwing [DatabaseOpenFailedError] when the check finds a problem.
Future<void> _openHealthy(LocalDatabase db, String name) async {
  try {
    await db.open();
    final rows = await db.rawQuery('PRAGMA quick_check');
    final verdict = rows.isEmpty ? null : rows.first.values.first.asString;
    if (verdict != 'ok') {
      throw DatabaseOpenFailedError('$name is corrupted: quick_check answered $verdict');
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
