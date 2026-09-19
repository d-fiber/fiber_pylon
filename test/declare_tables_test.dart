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

// A schema-validation check like test/typed_database_test.dart: declaring tables
// after the file was opened is proven against a real SQLite file.

import 'dart:io';

import 'package:fiber_pylon/src/sdk/clients/local/database/engine/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

final class Note {
  const Note({this.id, required this.title, this.pinned});

  final int? id;
  final String title;
  final bool? pinned;
}

final class Notes extends KeyedTable<Note, int> {
  Notes() : super('notes');

  late final id = column.key();
  late final title = column.text('title');

  @override
  List<Field<Object?>> get columns => [id, title];

  @override
  Note read(Reader row) => Note(id: row(id), title: row(title));

  @override
  List<Assignment> write(Note note) => [id.toOrGenerate(note.id), title.to(note.title)];
}

/// The same table, with a nullable column more: what a later version declares.
final class NotesV2 extends KeyedTable<Note, int> {
  NotesV2() : super('notes');

  late final id = column.key();
  late final title = column.text('title');
  late final pinned = column.boolean('pinned').nullable();

  @override
  List<Field<Object?>> get columns => [id, title, pinned];

  @override
  Note read(Reader row) => Note(id: row(id), title: row(title), pinned: row(pinned));

  @override
  List<Assignment> write(Note note) => [id.toOrGenerate(note.id), title.to(note.title), pinned.to(note.pinned)];
}

/// A column that is neither nullable nor defaulted: it cannot be added to a
/// table that already holds rows.
final class NotesBroken extends KeyedTable<Note, int> {
  NotesBroken() : super('notes');

  late final id = column.key();
  late final title = column.text('title');
  late final owner = column.text('owner');

  @override
  List<Field<Object?>> get columns => [id, title, owner];

  @override
  Note read(Reader row) => Note(id: row(id), title: row(title));

  @override
  List<Assignment> write(Note note) => [id.toOrGenerate(note.id), title.to(note.title), owner.to('x')];
}

final class Tag {
  const Tag({this.id, required this.noteId, required this.label});

  final int? id;
  final int noteId;
  final String label;
}

final class Tags extends KeyedTable<Tag, int> {
  Tags(this.notes) : super('tags');

  final Notes notes;

  late final id = column.key();
  late final noteId = column.integer('note_id').references(notes.id);
  late final label = column.text('label');

  @override
  List<Field<Object?>> get columns => [id, noteId, label];

  @override
  Tag read(Reader row) => Tag(id: row(id), noteId: row(noteId), label: row(label));

  @override
  List<Assignment> write(Tag tag) => [id.toOrGenerate(tag.id), noteId.to(tag.noteId), label.to(tag.label)];
}

final class Private {
  const Private({this.id, required this.text});

  final int? id;
  final String text;
}

final class Privates extends KeyedTable<Private, int> {
  Privates() : super('privates');

  late final id = column.key();
  late final text = column.text('text');

  @override
  Tunnel get tunnel => Tunnel.isolated;

  @override
  List<Field<Object?>> get columns => [id, text];

  @override
  Private read(Reader row) => Private(id: row(id), text: row(text));

  @override
  List<Assignment> write(Private value) => [id.toOrGenerate(value.id), text.to(value.text)];
}

void main() {
  late Directory directory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    Tenant.leave();
    directory = await Directory.systemTemp.createTemp('pylon_declare');
    databaseFactoryFfi.setDatabasesPath(directory.path);
  });

  tearDown(() async {
    Tenant.leave();
    await directory.delete(recursive: true);
  });

  Future<LocalDatabase> plain([String name = 'declare.db']) async {
    final db = LocalDatabase(name: name);
    await db.open();
    return db;
  }

  group('LocalDatabase.declare', () {
    test('creates the tables of a database that was opened without any', () async {
      final db = await plain();
      final notes = Notes();

      await db.declareTables([notes]);

      expect(await db.hasTable('notes'), isTrue);
      await notes.on(db).insert(const Note(title: 'one'));
      expect((await notes.on(db).list()).single.title, 'one');
      await db.dispose();
    });

    test('is done once for the same declaration, and does nothing the second time', () async {
      final db = await plain();
      final notes = Notes();
      await db.declareTables([notes]);
      await notes.on(db).insert(const Note(title: 'kept'));

      await db.declareTables([notes]);
      await db.declareTables([Notes()]);

      expect((await notes.on(db).list()).single.title, 'kept');
      await db.dispose();
    });

    test('takes tables one call after another, foreign keys across calls included', () async {
      final db = await plain();
      final notes = Notes();
      await db.declareTables([notes]);
      final tags = Tags(notes);

      await db.declareTables([tags]);

      final note = await notes.on(db).insert(const Note(title: 'n'));
      await tags.on(db).insert(Tag(noteId: note.id!, label: 'x'));
      await expectLater(
        tags.on(db).insert(const Tag(noteId: 999, label: 'orphan')),
        throwsA(isA<ForeignKeyConstraintError>()),
      );
      await db.dispose();
    });

    test('refuses the same table declared differently, and leaves everything as it was', () async {
      final db = await plain();
      final notes = Notes();
      await db.declareTables([notes]);

      await expectLater(db.declareTables([NotesV2()]), throwsStateError);

      expect(await notes.on(db).count(), 0);
      await db.dispose();
    });

    test('adds a nullable column to a table another launch created', () async {
      final first = await plain();
      await first.declareTables([Notes()]);
      await Notes().on(first).insert(const Note(title: 'old'));
      await first.dispose();

      final second = await plain();
      final v2 = NotesV2();
      await second.declareTables([v2]);

      final rows = await v2.on(second).list();
      expect(rows.single.title, 'old');
      expect(rows.single.pinned, isNull);
      await second.dispose();
    });

    test('finds again the tables and rows a previous launch left', () async {
      final first = await plain();
      await first.declareTables([Notes()]);
      await Notes().on(first).insert(const Note(title: 'left'));
      await first.dispose();

      final second = await plain();
      final notes = Notes();
      await second.declareTables([notes]);

      expect((await notes.on(second).list()).single.title, 'left');
      await second.dispose();
    });

    test('a column that cannot be added stops the declaration and leaves the database as it was', () async {
      final first = await plain();
      await first.declareTables([Notes()]);
      await Notes().on(first).insert(const Note(title: 'old'));
      await first.dispose();

      final second = await plain();
      await expectLater(second.declareTables([NotesBroken()]), throwsA(isA<MigrationRequiredError>()));

      expect(await second.listColumns('notes').then((c) => c.map((x) => x.name)), ['id', 'title']);
      await second.dispose();
    });

    test('once tables were declared, a table that was not is refused', () async {
      final db = await plain();
      await db.declareTables([Notes()]);

      expect(() => Privates().on(db), throwsStateError);
      await db.dispose();
    });

    test('adds tables to a database opened with LocalDatabase.declared too', () async {
      final notes = Notes();
      final db = LocalDatabase.declared(name: 'both.db', tables: [notes]);
      await db.open();
      final privates = Privates();

      await db.declareTables([privates]);

      await privates.on(db).insert(const Private(text: 'p'));
      expect(await privates.on(db).count(), 1);
      await db.dispose();
    });

    test('an isolated table declared later is isolated all the same', () async {
      final db = await plain();
      final privates = Privates();
      await db.declareTables([privates]);
      Tenant.use('a');
      await privates.on(db).insert(const Private(text: 'a'));
      Tenant.use('b');

      expect(await privates.on(db).count(), 0);
      expect((await db.listColumns('privates')).map((c) => c.name), contains('__tenant'));
      await db.dispose();
    });

    test('takes two calls at once one after the other', () async {
      final db = await plain();
      final notes = Notes();
      final tags = Tags(notes);

      await Future.wait([
        db.declareTables([notes]),
        db.declareTables([tags]),
      ]);

      expect(await db.hasTable('notes'), isTrue);
      expect(await db.hasTable('tags'), isTrue);
      await db.dispose();
    });

    test('is refused on a read only database and on one that is closed', () async {
      final writable = await plain('ro.db');
      await writable.dispose();
      final readOnly = LocalDatabase(name: 'ro.db', readOnly: true);
      await readOnly.open();
      final closed = LocalDatabase(name: 'closed.db');

      await expectLater(readOnly.declareTables([Notes()]), throwsStateError);
      await expectLater(closed.declareTables([Notes()]), throwsStateError);
      await readOnly.dispose();
    });

    test('keeps working after a failed declaration', () async {
      final db = await plain();
      final notes = Notes();
      await db.declareTables([notes]);
      await expectLater(db.declareTables([NotesV2()]), throwsStateError);

      await db.declareTables([Privates()]);

      expect(await db.hasTable('privates'), isTrue);
      await db.dispose();
    });
  });
}
