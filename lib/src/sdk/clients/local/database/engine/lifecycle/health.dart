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

/// Whether the file of the app database is encrypted.
enum EncryptionPolicy {
  /// Always: the app refuses to start on a SQLite that cannot encrypt, rather
  /// than keep its data in clear.
  required,

  /// Where SQLCipher exists (Android, iOS and macOS) and in clear elsewhere,
  /// which [LocalDatabase.isEncrypted] then says. The default.
  whenAvailable,

  /// Never. For a test, or a platform with no SQLCipher that must still run.
  off,
}

/// Whether the platform this app runs on has SQLCipher to encrypt with.
bool get _sqlCipherSupported => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

final RegExp _lowerThenUpper = RegExp(r'([a-z0-9])([A-Z])');
final RegExp _acronymThenWord = RegExp(r'([A-Z]+)([A-Z][a-z])');
final RegExp _notLetterOrDigit = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// [appName] in snake case: words split where the case changes or where a
/// character is neither a letter nor a digit, lower-cased, joined by `_`.
/// `MyApp`, `My App` and `my-app` all give `my_app`. A name with no letter or
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

/// The file name the app's database gets: [appName] in snake case followed by
/// `.db`.
String _fileName(String appName) => '${_snakeCase(appName)}.db';

/// Opens `<app name>.db` and hands it back healthy, whatever state the file
/// was left in:
///
/// - it does not exist yet (first launch, or deleted since the last one):
///   SQLite creates it empty;
/// - it exists and reads fine: it is used as it is, nothing is recreated;
/// - it exists but cannot be opened, or `PRAGMA quick_check` finds it
///   corrupted: it is deleted, along with its `-wal`, `-shm` and `-journal`
///   siblings, and created again. Its content is lost, since there is
///   nothing left in it to read.
///
/// The app's name is read from the platform through `package_info_plus`
/// unless [appName] is given. [factory] defaults to sqflite's own
/// [databaseFactory].
///
/// Throws the [StoreError] the second attempt fails with, when even a fresh
/// file cannot be opened (a directory this process may not write to, say):
/// recreating cannot fix that.
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

Future<void> _deleteFiles(String path, DatabaseFactory factory) async {
  await factory.deleteDatabase(path);
  for (final suffix in const ['-wal', '-shm', '-journal']) {
    final sibling = File('$path$suffix');
    if (await sibling.exists()) await sibling.delete();
  }
}
