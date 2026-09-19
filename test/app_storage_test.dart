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
// A schema-validation check like test/local_database_test.dart: it opens real,
// temporary SQLite files through `sqflite_common_ffi`, since a corrupted file
// is something no fake can stand in for.

import 'dart:io';

import 'package:fiber_pylon/di/di.dart';
import 'package:fiber_pylon/fiber_pylon.dart';
import 'package:fiber_pylon/src/sdk/clients/local/database/engine/database.dart';
import 'package:fiber_pylon/src/sdk/clients/local/database/engine/app.dart' show openAppDatabase;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

class _Note implements Storable {
  const _Note(this.body);

  final String body;

  @override
  RawRow toRow() => {'body': Value.varchar(body)};
}

Future<List<String>> _bodies() =>
    AppStorage.query<String>(SecureStorage.fingerprint, (q) => q.from('notes').map((row) => row['body']!.asString));

const _fingerprintName = 'pylon.fingerprint.v1';

void main() {
  late Directory directory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pylon_app_storage');
    databaseFactoryFfi.setDatabasesPath(directory.path);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  File file(String name) => File(p.join(directory.path, name));

  group('openAppDatabase', () {
    test('creates <app>.db on the first launch', () async {
      expect(file('Fiber.db').existsSync(), isFalse);

      final db = await openAppDatabase(appName: 'Fiber');

      expect(db.isOpen, isTrue);
      expect(file('Fiber.db').existsSync(), isTrue);
      await db.dispose();
    });

    test('replaces characters a file name cannot hold', () async {
      final db = await openAppDatabase(appName: 'a/b:c');

      expect(file('a_b_c.db').existsSync(), isTrue);
      await db.dispose();
    });

    test('falls back to app.db when the name is empty', () async {
      final db = await openAppDatabase(appName: '  ');

      expect(file('app.db').existsSync(), isTrue);
      await db.dispose();
    });

    test('keeps using the file it finds', () async {
      final first = await openAppDatabase(appName: 'Fiber');
      await first.runSql('CREATE TABLE notes (body TEXT)');
      await first.runSql('INSERT INTO notes (body) VALUES (?)', [const Value.varchar('kept')]);
      await first.dispose();

      final second = await openAppDatabase(appName: 'Fiber');

      final rows = await second.runRawQuery('SELECT body FROM notes');
      expect(rows.single['body']!.asString, 'kept');
      await second.dispose();
    });

    test('creates it again when it was deleted in between', () async {
      final first = await openAppDatabase(appName: 'Fiber');
      await first.dispose();
      file('Fiber.db').deleteSync();

      final second = await openAppDatabase(appName: 'Fiber');

      expect(file('Fiber.db').existsSync(), isTrue);
      expect(await second.listTables(), isEmpty);
      await second.dispose();
    });

    test('deletes and recreates a file that is not a database', () async {
      file('Fiber.db').writeAsStringSync('this is not sqlite ' * 100);

      final db = await openAppDatabase(appName: 'Fiber');

      await db.runSql('CREATE TABLE notes (body TEXT)');
      expect(await db.listTables(), ['notes']);
      await db.dispose();
    });
  });

  group('the fingerprint and the encryption of the app database', () {
    setUp(() {
      PackageInfo.setMockInitialValues(
        appName: 'Fiber',
        packageName: 'dev.fiber.app',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      AppStorage.encryption = EncryptionPolicy.off;
    });

    tearDown(() => GetIt.instance.reset());

    test('the first launch creates the fingerprint and keeps it in the vault', () async {
      const vault = FlutterSecureStorage();
      expect(await vault.read(key: _fingerprintName), isNull);

      await GetIt.instance.reset();
      await configureSdk();

      expect(await vault.read(key: _fingerprintName), isNotNull);
    });

    test('the next launch finds the same fingerprint instead of making another', () async {
      await GetIt.instance.reset();
      await configureSdk();
      final first = SecureStorage.fingerprint.derive('database').join(',');
      final kept = await const FlutterSecureStorage().read(key: _fingerprintName);

      await GetIt.instance.reset();
      await configureSdk();

      expect(SecureStorage.fingerprint.derive('database').join(','), first);
      expect(await const FlutterSecureStorage().read(key: _fingerprintName), kept);
    });

    test('an invalid record in the vault stops the launch and is left alone', () async {
      FlutterSecureStorage.setMockInitialValues({_fingerprintName: 'garbage'});
      await GetIt.instance.reset();

      await expectLater(configureSdk(), throwsStateError);

      expect(await const FlutterSecureStorage().read(key: _fingerprintName), 'garbage');
    });

    test('says when the file is not encrypted', () async {
      await GetIt.instance.reset();
      await configureSdk();

      expect(AppStorage.isEncrypted, isFalse);
    });

    test('a database opened with the app fingerprint opens the whole-database mechanism', () async {
      final fingerprint = Fingerprint.generate();
      final db = await openAppDatabase(appName: 'Fiber', fingerprint: fingerprint, encryption: EncryptionPolicy.off);

      expect(db.wholeDatabase(fingerprint), isNotNull);
      expect(() => db.wholeDatabase(Fingerprint.generate()), throwsStateError);
      await db.dispose();
    });

    test('a required encryption refuses to run without SQLCipher, and leaves no file in clear', () async {
      await expectLater(
        openAppDatabase(
          appName: 'Fiber',
          factory: databaseFactoryFfi,
          fingerprint: Fingerprint.generate(),
          encryption: EncryptionPolicy.required,
        ),
        throwsA(isA<EncryptionUnavailableError>()),
      );

      expect(file('Fiber.db').existsSync(), isFalse);
    });

    test('never deletes a database in clear to encrypt over it', () async {
      final clear = await openAppDatabase(appName: 'Fiber');
      await clear.runSql('CREATE TABLE precious (x TEXT)');
      await clear.dispose();
      final before = file('Fiber.db').readAsBytesSync();

      await expectLater(
        openAppDatabase(
          appName: 'Fiber',
          factory: databaseFactoryFfi,
          fingerprint: Fingerprint.generate(),
          encryption: EncryptionPolicy.required,
        ),
        throwsStateError,
      );

      expect(file('Fiber.db').readAsBytesSync(), before);
    });

    test('without a fingerprint nothing is encrypted, whatever the policy', () async {
      final db = await openAppDatabase(appName: 'Fiber', encryption: EncryptionPolicy.required);

      expect(db.encrypted, isFalse);
      await db.dispose();
    });
  });

  group('AppStorage', () {
    setUp(() async {
      PackageInfo.setMockInitialValues(
        appName: 'Fiber',
        packageName: 'dev.fiber.app',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      AppStorage.encryption = EncryptionPolicy.off;
      await GetIt.instance.reset();
      await configureSdk();
    });

    tearDown(() => GetIt.instance.reset());

    test('the raw calls show the whole database only to the app fingerprint', () async {
      await AppStorage.execute(SecureStorage.fingerprint, 'CREATE TABLE IF NOT EXISTS notes (body TEXT)');

      expect(await AppStorage.tableNames(SecureStorage.fingerprint), ['notes']);
      expect(() => AppStorage.tableNames(Fingerprint.generate()), throwsStateError);
      expect(() => AppStorage.execute(Fingerprint.generate(), 'DROP TABLE notes'), throwsStateError);
      expect(() => AppStorage.rawQuery(Fingerprint.generate(), 'SELECT 1'), throwsStateError);
      expect(() => AppStorage.batch(Fingerprint.generate()), throwsStateError);
      expect(await AppStorage.tableExists(SecureStorage.fingerprint, 'notes'), isTrue);
    });

    test('opens <app>.db once configureSdk has run', () {
      expect(file('Fiber.db').existsSync(), isTrue);
    });

    test('reads and writes through static insert, query, update and delete', () async {
      await AppStorage.execute(
        SecureStorage.fingerprint,
        'CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY AUTOINCREMENT, body TEXT)',
      );

      final id = await AppStorage.insert<_Note>(
        SecureStorage.fingerprint,
        (i) => i.into('notes').values(const _Note('first')),
      );
      await AppStorage.update<_Note>(
        SecureStorage.fingerprint,
        (u) => u
            .table('notes')
            .set(const _Note('second'))
            .where((w) => w.isEqualTo(key: 'id', value: Value.integer(id))),
      );
      expect(await _bodies(), ['second']);

      await AppStorage.delete(SecureStorage.fingerprint, (d) => d.from('notes'));
      expect(await _bodies(), isEmpty);
    });

    test('stays open across calls, with no reopening in between', () async {
      await AppStorage.execute(SecureStorage.fingerprint, 'CREATE TABLE IF NOT EXISTS notes (body TEXT)');
      await AppStorage.execute(SecureStorage.fingerprint, 'INSERT INTO notes (body) VALUES (?)', [
        const Value.varchar('x'),
      ]);

      expect(await AppStorage.tableNames(SecureStorage.fingerprint), ['notes']);
      expect(await AppStorage.tableExists(SecureStorage.fingerprint, 'notes'), isTrue);
      expect(await _bodies(), ['x']);
    });

    test('commits a transaction', () async {
      await AppStorage.execute(SecureStorage.fingerprint, 'CREATE TABLE IF NOT EXISTS notes (body TEXT)');

      await AppStorage.transaction(
        SecureStorage.fingerprint,
        (txn) => txn.insert<_Note>((i) => i.into('notes').values(const _Note('in txn'))),
      );

      expect(await _bodies(), ['in txn']);
    });
  });
}
