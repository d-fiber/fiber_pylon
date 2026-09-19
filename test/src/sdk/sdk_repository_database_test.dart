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

// A check against a real SQLite file, through `sqflite_common_ffi`: what an
// SdkRepository reads is the database's own stream, and only a real one moves with a
// write and with a change of tenant.

import 'dart:io';

import 'package:fiber_pylon/di/di.dart';
import 'package:fiber_pylon/fiber_pylon.dart' hide Database;
import 'package:fiber_pylon/fiber_pylon.dart' as pylon show Database;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart' hide Database;

enum HouseSignal { noRoute, unknown }

enum HouseError { unknown }

final class Note {
  const Note({required this.id, required this.title});

  final String id;
  final String title;

  @override
  bool operator ==(Object other) => other is Note && other.id == id && other.title == title;

  @override
  int get hashCode => Object.hash(id, title);

  @override
  String toString() => 'Note($id, $title)';
}

final class NotesTable extends KeyedTable<Note, String> {
  NotesTable() : super('notes');

  late final id = column.text('id').primaryKey();
  late final title = column.text('title');

  @override
  Tunnel get tunnel => Tunnel.isolated;

  @override
  List<Field<Object?>> get columns => [id, title];

  @override
  Note read(Reader row) => Note(id: row(id), title: row(title));

  @override
  List<Assignment> write(Note note) => [id.to(note.id), title.to(note.title)];
}

final class NotesDatabase extends pylon.Database {
  final notes = NotesTable();

  @override
  List<KeyedTable<Object, Object>> get tables => [notes];
}

final class NotesList extends SdkRepository<List<Note>, List<Note>, HouseError, HouseSignal> {
  NotesList(this._database, this.answer) : super(offlineSignals: const {HouseSignal.noRoute});

  final NotesDatabase _database;
  List<Note> answer;

  @override
  bool get isAuthenticated => false;

  @override
  bool get observesConnection => true;

  @override
  Future<List<Note>> fetch() async => answer;

  @override
  Future<void> response(List<Note> response) => _database.runTransaction((transaction) async {
    for (final note in response) {
      await transaction.from(_database.notes).upsert(note);
    }
  });

  @override
  Stream<List<Note>> stream() => _database.from(_database.notes).orderBy((o) => o.asc(_database.notes.id)).stream();

  @override
  HouseError resolve(Fault<HouseSignal> fault) => HouseError.unknown;
}

Future<List<Note>> becomes(NotesList call, bool Function(List<Note> notes) test) => call.data.stream
    .where((notes) => notes != null)
    .map((notes) => notes!)
    .firstWhere(test)
    .timeout(const Duration(seconds: 5));

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory directory;
  late NotesDatabase database;

  setUp(() async {
    Tenant.leave();
    directory = await Directory.systemTemp.createTemp('pylon_sdk_call');
    databaseFactoryFfi.setDatabasesPath(directory.path);
    PackageInfo.setMockInitialValues(
      appName: 'pylon_test',
      packageName: 'dev.fiber.pylon_test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    LocalDatabase.encryption = EncryptionPolicy.off;
    await GetIt.instance.reset();
    await configureSdk();
    database = NotesDatabase();
    await database.initialize();
  });

  tearDown(() async {
    Tenant.leave();
    await database.dispose();
    await GetIt.instance.reset();
    await directory.delete(recursive: true);
  });

  group('SdkRepository over a real database', () {
    test('follows what a refresh writes', () async {
      final call = NotesList(database, [const Note(id: 'a', title: 'first')]);
      addTearDown(call.dispose);
      await becomes(call, (notes) => notes.isEmpty);

      final status = await call.refresh();

      expect(status, const StatusSucceeded<HouseError>());
      expect(await becomes(call, (notes) => notes.isNotEmpty), [const Note(id: 'a', title: 'first')]);
      expect(call.data.value, [const Note(id: 'a', title: 'first')]);
    });

    test('reads what an earlier launch stored before any refresh', () async {
      await database.from(database.notes).upsert(const Note(id: 'old', title: 'kept'));
      final call = NotesList(database, []);
      addTearDown(call.dispose);

      expect(call.data.value, isNull);

      expect(await becomes(call, (notes) => notes.isNotEmpty), [const Note(id: 'old', title: 'kept')]);
      expect(call.status.value, const StatusIdle<HouseError>());
    });

    test('keeps what is stored when the network is out of reach', () async {
      await database.from(database.notes).upsert(const Note(id: 'old', title: 'kept'));
      final call = _Unreachable(database);
      addTearDown(call.dispose);
      await becomes(call, (notes) => notes.isNotEmpty);

      final status = await call.refresh();

      expect(status, const StatusOffline<HouseError>());
      expect(call.data.value, [const Note(id: 'old', title: 'kept')]);
    });

    test('reads the rows of whoever is signed in, and swaps them with the tenant', () async {
      final call = NotesList(database, [const Note(id: 'a1', title: 'ada note')]);
      addTearDown(call.dispose);
      Tenant.use('ada');
      await call.refresh();
      await becomes(call, (notes) => notes.isNotEmpty);

      Tenant.use('bob');
      expect(await becomes(call, (notes) => notes.isEmpty), isEmpty);
      call.answer = [const Note(id: 'b1', title: 'bob note')];
      await call.refresh();
      expect(await becomes(call, (notes) => notes.isNotEmpty), [const Note(id: 'b1', title: 'bob note')]);

      Tenant.use('ada');
      expect(await becomes(call, (notes) => notes.any((note) => note.id == 'a1')), [
        const Note(id: 'a1', title: 'ada note'),
      ]);
    });
  });
}

final class _Unreachable extends NotesList {
  _Unreachable(NotesDatabase database) : super(database, const []);

  @override
  Future<List<Note>> fetch() async => throw const Fault<HouseSignal>(HouseSignal.noRoute);
}
