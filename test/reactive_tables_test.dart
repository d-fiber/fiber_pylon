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

// A schema-validation check like test/typed_database_test.dart: watching a
// table is only proven by real writes to a real SQLite file, through
// `sqflite_common_ffi`.

import 'dart:io';

import 'package:fiber_pylon/src/sdk/clients/local/database/engine/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

final class Note {
  const Note({this.id, required this.title, this.done = false});

  final int? id;
  final String title;
  final bool done;
}

final class Notes extends KeyedTable<Note, int> {
  Notes() : super('notes');

  late final id = column.key();
  late final title = column.text('title');
  late final done = column.boolean('done').defaultsTo(false);

  @override
  List<Field<Object?>> get columns => [id, title, done];

  @override
  Note read(Reader row) => Note(id: row(id), title: row(title), done: row(done));

  @override
  List<Assignment> write(Note note) => [id.toOrGenerate(note.id), title.to(note.title), done.to(note.done)];
}

final class Tags extends KeyedTable<String, int> {
  Tags() : super('tags');

  late final id = column.key();
  late final label = column.text('label');

  @override
  List<Field<Object?>> get columns => [id, label];

  @override
  String read(Reader row) => row(label);

  @override
  List<Assignment> write(String value) => [label.to(value)];
}

/// Waits until [list] holds [count] items: the next event needs a real
/// database round trip, which no fixed number of event-loop turns covers.
Future<void> _waitFor(List<Object?> list, int count) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (list.length < count) {
    if (DateTime.now().isAfter(deadline)) fail('Waited for $count event(s), got ${list.length}.');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  late Directory directory;
  late Notes notes;
  late Tags tags;
  late LocalDatabase db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pylon_reactive_tables');
    databaseFactoryFfi.setDatabasesPath(directory.path);
    notes = Notes();
    tags = Tags();
    db = LocalDatabase.declared(name: 'reactive.db', tables: [notes, tags]);
    await db.open();
  });

  tearDown(() async {
    await db.dispose();
    await directory.delete(recursive: true);
  });

  group('Rows.watch', () {
    test('sends the current rows first, then one event per change', () async {
      await notes.on(db).insert(const Note(title: 'one'));
      final events = <List<String>>[];
      final subscription = notes
          .on(db)
          .orderBy([notes.id.asc()])
          .watch()
          .listen((rows) => events.add([for (final row in rows) row.title]));
      await _waitFor(events, 1);

      await notes.on(db).insert(const Note(title: 'two'));
      await _waitFor(events, 2);
      await notes.on(db).where(notes.title.isEqualTo('one')).update([notes.title.to('uno')]);
      await _waitFor(events, 3);
      await notes.on(db).where(notes.title.isEqualTo('two')).delete();
      await _waitFor(events, 4);
      await subscription.cancel();

      expect(events, [
        ['one'],
        ['one', 'two'],
        ['uno', 'two'],
        ['uno'],
      ]);
    });

    test('sends nothing for a write to another table', () async {
      final events = <int>[];
      final subscription = notes.on(db).watch().listen((rows) => events.add(rows.length));
      await _waitFor(events, 1);

      await tags.on(db).insert('x');
      await _settle();
      await subscription.cancel();

      expect(events, [0]);
    });

    test('sends nothing when a write leaves the kept rows as they were', () async {
      final events = <int>[];
      final subscription = notes
          .on(db)
          .where(notes.done.isEqualTo(true))
          .watch()
          .listen((rows) => events.add(rows.length));
      await _waitFor(events, 1);

      await notes.on(db).insert(const Note(title: 'not done'));
      await notes.on(db).insert(const Note(title: 'done', done: true));
      await _waitFor(events, 2);
      await subscription.cancel();

      expect(events, [0, 1]);
    });

    test('sends nothing for an update that changes no row', () async {
      await notes.on(db).insert(const Note(title: 'one'));
      final events = <int>[];
      final subscription = notes.on(db).watch().listen((rows) => events.add(rows.length));
      await _waitFor(events, 1);

      final changed = await notes.on(db).where(notes.title.isEqualTo('nothing')).update([notes.done.to(true)]);
      await _settle();
      await subscription.cancel();

      expect(changed, 0);
      expect(events, [1]);
    });

    test('hears an upsert, whether it inserts or updates', () async {
      final events = <List<String>>[];
      final subscription = notes.on(db).watch().listen((rows) => events.add([for (final r in rows) r.title]));
      await _waitFor(events, 1);

      final first = await notes.on(db).upsert(const Note(title: 'a'));
      await _waitFor(events, 2);
      await notes.on(db).upsert(Note(id: first.id, title: 'b'));
      await _waitFor(events, 3);
      await subscription.cancel();

      expect(events, [
        <String>[],
        ['a'],
        ['b'],
      ]);
    });

    test('stops sending once cancelled', () async {
      final events = <int>[];
      final subscription = notes.on(db).watch().listen((rows) => events.add(rows.length));
      await _waitFor(events, 1);
      await subscription.cancel();

      await notes.on(db).insert(const Note(title: 'late'));
      await _settle();

      expect(events, [0]);
    });

    test('reads nothing until it is listened to', () async {
      final stream = notes.on(db).watch();
      await notes.on(db).insert(const Note(title: 'before'));

      final first = await stream.first;

      expect(first.map((note) => note.title), ['before']);
    });

    test('serves several listeners at once', () async {
      final left = <int>[];
      final right = <int>[];
      final a = notes.on(db).watch().listen((rows) => left.add(rows.length));
      final b = notes.on(db).where(notes.done.isEqualTo(true)).watch().listen((rows) => right.add(rows.length));
      await _waitFor(left, 1);
      await _waitFor(right, 1);

      await notes.on(db).insert(const Note(title: 'x', done: true));
      await _waitFor(left, 2);
      await _waitFor(right, 2);
      await a.cancel();
      await b.cancel();

      expect(left, [0, 1]);
      expect(right, [0, 1]);
    });

    test('refuses a session that is a transaction', () async {
      await db.transaction((txn) async {
        expect(() => notes.on(txn).watch(), throwsStateError);
        expect(() => notes.on(txn).watchFirst(), throwsStateError);
      });
    });
  });

  group('watchFirst, watchCount and watchOne', () {
    test('watchFirst follows the first row of an ordering', () async {
      final events = <String?>[];
      final subscription = notes
          .on(db)
          .orderBy([notes.title.asc()])
          .watchFirst()
          .listen((note) => events.add(note?.title));
      await _waitFor(events, 1);

      await notes.on(db).insert(const Note(title: 'm'));
      await _waitFor(events, 2);
      await notes.on(db).insert(const Note(title: 'z'));
      await notes.on(db).insert(const Note(title: 'a'));
      await _waitFor(events, 3);
      await subscription.cancel();

      expect(events, [null, 'm', 'a']);
    });

    test('watchCount sends the number only when it changes', () async {
      final events = <int>[];
      final subscription = notes.on(db).watchCount().listen(events.add);
      await _waitFor(events, 1);

      final one = await notes.on(db).insert(const Note(title: 'a'));
      await _waitFor(events, 2);
      await notes.on(db).where(notes.id.isEqualTo(one.id!)).update([notes.title.to('b')]);
      await _settle();
      await notes.on(db).insert(const Note(title: 'c'));
      await _waitFor(events, 3);
      await subscription.cancel();

      expect(events, [0, 1, 2]);
    });

    test('watchCount refuses a page', () {
      expect(() => notes.on(db).limit(1).watchCount(), throwsStateError);
    });

    test('watchOne follows one key from absent to present to changed to gone', () async {
      final events = <String?>[];
      final subscription = notes.on(db).watchOne(7).listen((note) => events.add(note?.title));
      await _waitFor(events, 1);

      await notes.on(db).insert(const Note(id: 7, title: 'seven'));
      await _waitFor(events, 2);
      await notes.on(db).upsert(const Note(id: 7, title: 'VII'));
      await _waitFor(events, 3);
      await notes.on(db).remove(7);
      await _waitFor(events, 4);
      await subscription.cancel();

      expect(events, [null, 'seven', 'VII', null]);
    });
  });

  group('transactions, batches and raw writes', () {
    test('a transaction is heard once, after it commits', () async {
      final events = <int>[];
      final subscription = notes.on(db).watch().listen((rows) => events.add(rows.length));
      await _waitFor(events, 1);

      await db.transaction((txn) async {
        await notes.on(txn).insert(const Note(title: 'a'));
        await notes.on(txn).insert(const Note(title: 'b'));
        await _settle();
        expect(events, [0], reason: 'nothing is heard while the transaction is still open');
      });
      await _waitFor(events, 2);
      await _settle();
      await subscription.cancel();

      expect(events, [0, 2]);
    });

    test('a rolled back transaction is never heard', () async {
      final events = <int>[];
      final subscription = notes.on(db).watch().listen((rows) => events.add(rows.length));
      await _waitFor(events, 1);

      await expectLater(
        db.transaction((txn) async {
          await notes.on(txn).insert(const Note(title: 'a'));
          throw StateError('nope');
        }),
        throwsStateError,
      );
      await _settle();
      await subscription.cancel();

      expect(events, [0]);
    });

    test('an upsert is one atomic write, heard once', () async {
      final events = <int>[];
      final subscription = notes.on(db).watch().listen((rows) => events.add(rows.length));
      await _waitFor(events, 1);

      await notes.on(db).upsert(const Note(id: 1, title: 'a'));
      await _waitFor(events, 2);
      await _settle();
      await subscription.cancel();

      expect(events, [0, 1]);
    });

    test('an untyped insert, update and delete are heard', () async {
      final events = <int>[];
      final subscription = notes.on(db).watch().listen((rows) => events.add(rows.length));
      await _waitFor(events, 1);

      await db.insert<_Raw>((i) => i.into('notes').values(const _Raw('raw')));
      await _waitFor(events, 2);
      await db.delete((d) => d.from('notes'));
      await _waitFor(events, 3);
      await subscription.cancel();

      expect(events, [0, 1, 0]);
    });

    test('a batch and a raw execute tell every watcher', () async {
      final events = <int>[];
      final subscription = notes.on(db).watch().listen((rows) => events.add(rows.length));
      await _waitFor(events, 1);

      final batch = db.batch()..insert<_Raw>((i) => i.into('notes').values(const _Raw('a')));
      await batch.commit();
      await _waitFor(events, 2);
      await db.execute("INSERT INTO notes (title) VALUES ('b')");
      await _waitFor(events, 3);
      await subscription.cancel();

      expect(events, [0, 1, 2]);
    });

    test('a write inside a transaction through the database itself is held too', () async {
      final events = <int>[];
      final subscription = notes.on(db).watch().listen((rows) => events.add(rows.length));
      await _waitFor(events, 1);

      await db.transaction((txn) async {
        await notes.on(db).insert(const Note(title: 'a'));
        await _settle();
        expect(events, [0]);
      });
      await _waitFor(events, 2);
      await subscription.cancel();

      expect(events, [0, 1]);
    });
  });
}

final class _Raw implements Storable {
  const _Raw(this.title);

  final String title;

  @override
  RawRow toRow() => {'title': Value.varchar(title)};
}
