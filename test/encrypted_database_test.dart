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

// The encryption itself belongs to SQLCipher, which the desktop test runner
// does not have. What is proven here is everything around it: that a key is
// derived from the fingerprint and handed over as the password, that nothing
// is ever written in clear when encryption was asked for, and that a database
// asked to encrypt without a fingerprint is refused.

import 'dart:io';

import 'package:fiber_pylon/fiber_pylon.dart' hide Database, Tenant, Tunnel, TransferConflict;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';
import 'package:sqflite_sqlcipher/sqlite_api.dart' show SqlCipherOpenDatabaseOptions;

/// Opens through the desktop factory, and keeps the options it was asked for.
final class RecordingFactory implements DatabaseFactory {
  RecordingFactory(this._inner);

  final DatabaseFactory _inner;
  final List<OpenDatabaseOptions> requested = [];

  @override
  Future<Database> openDatabase(String path, {OpenDatabaseOptions? options}) {
    requested.add(options!);
    return _inner.openDatabase(
      path,
      options: OpenDatabaseOptions(
        onConfigure: options.onConfigure,
        readOnly: options.readOnly,
        singleInstance: options.singleInstance,
      ),
    );
  }

  @override
  Future<void> deleteDatabase(String path) => _inner.deleteDatabase(path);

  @override
  Future<String> getDatabasesPath() => _inner.getDatabasesPath();

  @override
  Future<void> setDatabasesPath(String path) => _inner.setDatabasesPath(path);

  @override
  Future<bool> databaseExists(String path) => _inner.databaseExists(path);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  late Directory directory;
  late RecordingFactory factory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pylon_encrypted');
    databaseFactoryFfi.setDatabasesPath(directory.path);
    factory = RecordingFactory(databaseFactoryFfi);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  group('encrypting a LocalDatabase', () {
    test('needs a fingerprint to derive the key from', () {
      expect(() => LocalDatabase.forTesting(name: 'x.db', encrypt: true), throwsArgumentError);
      expect(() => LocalDatabase.declaredForTesting(name: 'x.db', tables: const [], encrypt: true), throwsArgumentError);
    });

    test('hands SQLCipher a key derived from the fingerprint, never the fingerprint itself', () async {
      final fingerprint = Fingerprint.generate();
      final db = LocalDatabase.forTesting(name: 'k.db', factory: factory, fingerprint: fingerprint, encrypt: true);

      await expectLater(db.open(), throwsA(isA<EncryptionUnavailableError>()));

      final options = factory.requested.single;
      expect(options, isA<SqlCipherOpenDatabaseOptions>());
      final password = (options as SqlCipherOpenDatabaseOptions).password;
      expect(password, _hex(fingerprint.derive('database')));
      expect(password, hasLength(64));
    });

    test('derives a different key for a different fingerprint', () async {
      final a = LocalDatabase.forTesting(name: 'a.db', factory: factory, fingerprint: Fingerprint.generate(), encrypt: true);
      final b = LocalDatabase.forTesting(name: 'b.db', factory: factory, fingerprint: Fingerprint.generate(), encrypt: true);

      await expectLater(a.open(), throwsA(isA<EncryptionUnavailableError>()));
      await expectLater(b.open(), throwsA(isA<EncryptionUnavailableError>()));

      final passwords = factory.requested.map((o) => (o as SqlCipherOpenDatabaseOptions).password).toList();
      expect(passwords[0], isNot(passwords[1]));
    });

    test('refuses to run on a SQLite that is not SQLCipher, and stays closed', () async {
      final db = LocalDatabase.forTesting(name: 'plain.db', fingerprint: Fingerprint.generate(), encrypt: true);

      await expectLater(db.open(), throwsA(isA<EncryptionUnavailableError>()));

      expect(db.isOpen, isFalse);
    });

    test('writes nothing into a database it refused to open', () async {
      final db = LocalDatabase.forTesting(name: 'empty.db', fingerprint: Fingerprint.generate(), encrypt: true);

      await expectLater(db.open(), throwsA(isA<EncryptionUnavailableError>()));

      final file = File('${directory.path}/empty.db');
      expect(!file.existsSync() || file.lengthSync() == 0, isTrue);
    });

    test('a database with a fingerprint but no encryption opens as any other', () async {
      final db = LocalDatabase.forTesting(name: 'plain_ok.db', factory: factory, fingerprint: Fingerprint.generate());

      await db.open();

      expect(db.isOpen, isTrue);
      expect(factory.requested.single, isNot(isA<SqlCipherOpenDatabaseOptions>()));
      await db.dispose();
    });
  });
}
