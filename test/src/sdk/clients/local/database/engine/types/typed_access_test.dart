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

import 'package:fiber_pylon/src/sdk/clients/local/database/engine/database.dart';
import 'package:fiber_pylon/src/sdk/clients/local/database/engine/schema/schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

final class Note implements Storable {
  const Note({required this.title, this.body});

  final String title;
  final String? body;

  @override
  RawRow toRow() => {
    'title': Value.varchar(title),
    'body': Value.nullable(body, Value.varchar),
  };
}

Future<void> _createNotes(Database db, int version) =>
    db.execute('CREATE TABLE notes (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, body TEXT)');

void main() {
  late Directory directory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pylon_typed_access');
    databaseFactoryFfi.setDatabasesPath(directory.path);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  Future<LocalDatabase> openWithNotes(String name, List<Note> notes) async {
    final db = LocalDatabase.forTesting(name: name, onCreate: _createNotes);
    await db.open();
    for (final note in notes) {
      await db.runInsert<Note>((i) => i.into('notes').values(note));
    }
    return db;
  }

  group('RowReading', () {
    test('required names the column when the row does not carry it', () async {
      final db = await openWithNotes('row_missing.db', const [Note(title: 'A')]);
      final row = (await db.runRawQuery('SELECT title FROM notes')).single;

      expect(
        () => row.required('titel'),
        throwsA(
          isA<StateError>().having((error) => error.message, 'message', allOf(contains('"titel"'), contains('title'))),
        ),
      );
      await db.dispose();
    });

    test('required names the column when it is NULL', () async {
      final db = await openWithNotes('row_null.db', const [Note(title: 'A')]);
      final row = (await db.runRawQuery('SELECT body FROM notes')).single;

      expect(
        () => row.required('body'),
        throwsA(isA<StateError>().having((error) => error.message, 'message', contains('"body"'))),
      );
      await db.dispose();
    });

    test('required answers the value of a column that is set', () async {
      final db = await openWithNotes('row_set.db', const [Note(title: 'A')]);
      final row = (await db.runRawQuery('SELECT title FROM notes')).single;

      expect(row.required('title').asString, 'A');
      await db.dispose();
    });

    test('nullable answers null for NULL and the value otherwise', () async {
      final db = await openWithNotes('row_nullable.db', const [Note(title: 'A'), Note(title: 'B', body: 'text')]);
      final rows = await db.runRawQuery('SELECT body FROM notes ORDER BY id');

      expect(rows.map((row) => row.nullable('body')?.asString), [null, 'text']);
      await db.dispose();
    });

    test('nullable still refuses a column the row does not carry', () async {
      final db = await openWithNotes('row_nullable_missing.db', const [Note(title: 'A')]);
      final row = (await db.runRawQuery('SELECT title FROM notes')).single;

      expect(
        () => row.nullable('body'),
        throwsA(isA<StateError>().having((error) => error.message, 'message', contains('"body"'))),
      );
      await db.dispose();
    });
  });

  group('Value.nullable', () {
    test('writes NULL for a null and the encoded value otherwise', () {
      expect(Value.nullable<String>(null, Value.varchar), const Value.nil());
      expect(Value.nullable('x', Value.varchar), const Value.varchar('x'));
    });
  });

  group('asList', () {
    test('refuses an element of the wrong type when it decodes, not when the element is read', () {
      Object? failure;
      try {
        const Value.varchar('["a"]').asList<int>();
      } on TypeError catch (error) {
        failure = error;
      }

      expect(failure, isNotNull);
    });
  });

  group('an any column in a strict table', () {
    test('keeps the text it was given, digits included', () async {
      final db = LocalDatabase.forTesting(name: 'strict_any.db');
      await db.open();
      final declared = TableBuilder('anys').strict().columns((c) => {'a': c.any()});
      await db.runSql(declared.statements.first);
      await db.runSql('INSERT INTO anys VALUES (?)', const [Value.varchar('007')]);

      final rows = await db.runRawQuery('SELECT a FROM anys');

      expect(rows.single.required('a'), const Value.varchar('007'));
      await db.dispose();
    });
  });

  group('a column declared autoincrement', () {
    test('is a primary key even when isPrimary was never called', () {
      final declared = TableBuilder('z').columns((c) => {'a': c.integer().autoincrement()});

      expect(declared.statements.first, 'CREATE TABLE "z" ("a" INTEGER PRIMARY KEY AUTOINCREMENT)');
    });
  });
}
