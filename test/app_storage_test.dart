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
import 'package:fiber_pylon/src/storage/local_storage/app.dart' show openAppDatabase;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

class _Note implements DatabaseRecord {
  const _Note(this.body);

  final String body;

  @override
  DatabaseRow toRow() => {'body': DatabaseType.varchar(body)};
}

Future<List<String>> _bodies() => AppStorage.query<String>((q) => q.from('notes').map((row) => row['body']!.asString));

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
      await first.execute('CREATE TABLE notes (body TEXT)');
      await first.execute('INSERT INTO notes (body) VALUES (?)', [const DatabaseType.varchar('kept')]);
      await first.dispose();

      final second = await openAppDatabase(appName: 'Fiber');

      final rows = await second.rawQuery('SELECT body FROM notes');
      expect(rows.single['body']!.asString, 'kept');
      await second.dispose();
    });

    test('creates it again when it was deleted in between', () async {
      final first = await openAppDatabase(appName: 'Fiber');
      await first.dispose();
      file('Fiber.db').deleteSync();

      final second = await openAppDatabase(appName: 'Fiber');

      expect(file('Fiber.db').existsSync(), isTrue);
      expect(await second.tableNames(), isEmpty);
      await second.dispose();
    });

    test('deletes and recreates a file that is not a database', () async {
      file('Fiber.db').writeAsStringSync('this is not sqlite ' * 100);

      final db = await openAppDatabase(appName: 'Fiber');

      await db.execute('CREATE TABLE notes (body TEXT)');
      expect(await db.tableNames(), ['notes']);
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
      await GetIt.instance.reset();
      await configureSdk();
    });

    tearDown(() => GetIt.instance.reset());

    test('opens <app>.db once configureSdk has run', () {
      expect(file('Fiber.db').existsSync(), isTrue);
    });

    test('reads and writes through static insert, query, update and delete', () async {
      await AppStorage.execute('CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY AUTOINCREMENT, body TEXT)');

      final id = await AppStorage.insert<_Note>((i) => i.into('notes').values(const _Note('first')));
      await AppStorage.update<_Note>(
        (u) => u
            .table('notes')
            .set(const _Note('second'))
            .where((w) => w.isEqualTo(key: 'id', value: DatabaseType.integer(id))),
      );
      expect(await _bodies(), ['second']);

      await AppStorage.delete((d) => d.from('notes'));
      expect(await _bodies(), isEmpty);
    });

    test('stays open across calls, with no reopening in between', () async {
      await AppStorage.execute('CREATE TABLE IF NOT EXISTS notes (body TEXT)');
      await AppStorage.execute('INSERT INTO notes (body) VALUES (?)', [const DatabaseType.varchar('x')]);

      expect(await AppStorage.tableNames(), ['notes']);
      expect(await AppStorage.tableExists('notes'), isTrue);
      expect(await _bodies(), ['x']);
    });

    test('commits a transaction', () async {
      await AppStorage.execute('CREATE TABLE IF NOT EXISTS notes (body TEXT)');

      await AppStorage.transaction((txn) => txn.insert<_Note>((i) => i.into('notes').values(const _Note('in txn'))));

      expect(await _bodies(), ['in txn']);
    });
  });
}
