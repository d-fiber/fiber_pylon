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

part of '../database.dart';

/// A rule for whether the file of the app database is encrypted, see [LocalDatabase.encryption].
enum EncryptionPolicy {
  /// Always encrypted: the app refuses to start on a SQLite that cannot encrypt, rather than keep its data in clear.
  required,

  /// Encrypted where SQLCipher exists (Android, iOS and macOS) and in clear elsewhere, which
  /// [LocalDatabase.isEncrypted] then says. The default.
  whenAvailable,

  /// Never encrypted. For a test, or for a platform with no SQLCipher that must still run.
  off,
}

/// Whether the platform this app runs on has SQLCipher to encrypt with.
bool get _sqlCipherSupported => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

final RegExp _lowerThenUpper = RegExp(r'([a-z0-9])([A-Z])');
final RegExp _acronymThenWord = RegExp(r'([A-Z]+)([A-Z][a-z])');
final RegExp _notLetterOrDigit = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// [appName] in snake case, so that `MyApp`, `My App` and `my-app` all give `my_app`.
///
/// Words split where the case changes or where a character is neither a letter nor a digit. A name with no letter or
/// digit gives `app`.
String _snakeCase(String appName) {
  final words = appName
      .replaceAllMapped(_lowerThenUpper, (match) => '${match[1]}_${match[2]}')
      .replaceAllMapped(_acronymThenWord, (match) => '${match[1]}_${match[2]}')
      .toLowerCase()
      .replaceAll(_notLetterOrDigit, '_')
      .split('_')
      .where((word) => word.isNotEmpty);
  return words.isEmpty ? 'app' : words.join('_');
}

/// The file name the app database gets: [appName] in snake case followed by `.db`.
String _fileName(String appName) => '${_snakeCase(appName)}.db';

/// Opens the app database, named `<app name>.db`, and hands it back healthy whatever state its file was left in.
///
/// - The file does not exist yet, on a first launch or after it was deleted: SQLite creates it empty.
/// - The file exists and reads fine: it is used as it is.
/// - The file exists but cannot be opened, or `PRAGMA quick_check` finds it corrupted: it is deleted, along with its
///   `-wal`, `-shm` and `-journal` siblings, and created again. Its content is lost, since nothing in it can be read.
///
/// The app name is the one the platform reports through `package_info_plus` unless [appName] is given. [factory]
/// defaults to sqflite's [databaseFactory], or to the SQLCipher one when the database is encrypted. Whether it is
/// encrypted follows [encryption] and needs a [fingerprint].
///
/// Throws the [StoreError] the second attempt fails with, when even a fresh file cannot be opened, in a directory this
/// process may not write to for instance: recreating cannot fix that. Throws an [EncryptionUnavailableError] without
/// deleting anything when the database is to be encrypted on a SQLite that cannot. Throws a [StateError] when it is to
/// be encrypted and the file is a database in clear.
Future<LocalDatabase> _openAppDatabase({
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
  final db = LocalDatabase._app(name: name, factory: resolvedFactory, fingerprint: fingerprint, encrypt: encrypt);

  try {
    await _openHealthy(db, name);
  } on EncryptionUnavailableError {
    rethrow;
  } on StoreError {
    await _deleteFiles(path, resolvedFactory);
    await _openHealthy(db, name);
  }
  return db;
}

/// The first bytes of every SQLite file that is not encrypted.
const _clearFileHeader = 'SQLite format 3\u0000';

/// Throws a [StateError] if the file at [path] is a database in clear, so that it is not encrypted over.
///
/// Opening it with a key would fail as if it were corrupt and the repair would delete it, so a database from before
/// encryption existed would lose its data silently. The caller deletes it, or moves its rows over, on purpose.
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

/// Opens [db] and runs `PRAGMA quick_check` on it, and disposes it again if either step fails.
///
/// Throws an [OpenFailedError] when the check finds a problem.
Future<void> _openHealthy(LocalDatabase db, String name) async {
  try {
    await db.open();
    final rows = await db.runRawQuery('PRAGMA quick_check');
    final verdict = rows.isEmpty ? null : rows.first.values.first.asString;
    if (verdict != 'ok') {
      throw OpenFailedError('$name is corrupted: quick_check answered $verdict');
    }
  } catch (_) {
    await db.dispose();
    rethrow;
  }
}

/// Deletes the database file at [path] and its `-wal`, `-shm` and `-journal` siblings, which belong to the old file.
Future<void> _deleteFiles(String path, DatabaseFactory factory) async {
  await factory.deleteDatabase(path);
  for (final suffix in const ['-wal', '-shm', '-journal']) {
    final sibling = File('$path$suffix');
    if (await sibling.exists()) await sibling.delete();
  }
}
