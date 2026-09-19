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

// A schema-validation check like test/typed_database_test.dart: tenants are
// only proven by real rows in a real SQLite file, through `sqflite_common_ffi`.

import 'dart:io';

import 'package:fiber_pylon/fiber_pylon.dart' hide Database;
import 'package:fiber_pylon/src/sdk/clients/local/database/engine/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

final class Note {
  const Note({this.id, required this.title});

  final int? id;
  final String title;
}

/// Isolated, with an auto-numbered key.
final class Notes extends KeyedTable<Note, int> {
  Notes() : super('notes');

  late final id = column.key();
  late final title = column.text('title');

  @override
  Tunnel get tunnel => Tunnel.isolated;

  @override
  List<Field<Object?>> get columns => [id, title];

  @override
  Note read(Reader row) => Note(id: row(id), title: row(title));

  @override
  List<Assignment> write(Note note) => [id.toOrGenerate(note.id), title.to(note.title)];
}

final class Profile {
  const Profile(this.handle, this.email);

  final String handle;
  final String email;
}

/// Isolated, with a text key and a unique column: both unique per tenant.
final class Profiles extends KeyedTable<Profile, String> {
  Profiles() : super('profiles');

  late final handle = column.text('handle').primaryKey();
  late final email = column.text('email').unique();

  @override
  Tunnel get tunnel => Tunnel.isolated;

  @override
  List<Field<Object?>> get columns => [handle, email];

  @override
  Profile read(Reader row) => Profile(row(handle), row(email));

  @override
  List<Assignment> write(Profile profile) => [handle.to(profile.handle), email.to(profile.email)];
}

final class Comment {
  const Comment({this.id, required this.noteId, required this.text});

  final int? id;
  final int noteId;
  final String text;
}

/// Isolated, and pointing at an isolated table: a comment can only point at a
/// note of its own tenant.
final class Comments extends KeyedTable<Comment, int> {
  Comments(this.notes) : super('comments');

  final Notes notes;

  late final id = column.key();
  late final noteId = column.integer('note_id').references(notes.id);
  late final text = column.text('text');

  @override
  Tunnel get tunnel => Tunnel.isolated;

  @override
  List<Field<Object?>> get columns => [id, noteId, text];

  @override
  Comment read(Reader row) => Comment(id: row(id), noteId: row(noteId), text: row(text));

  @override
  List<Assignment> write(Comment comment) => [
    id.toOrGenerate(comment.id),
    noteId.to(comment.noteId),
    text.to(comment.text),
  ];
}

final class Setting {
  const Setting(this.name, this.value);

  final String name;
  final String value;
}

/// Shared, the default: one copy for everyone, with no tenant column at all.
final class Settings extends KeyedTable<Setting, String> {
  Settings() : super('settings');

  late final name = column.text('name').primaryKey();
  late final value = column.text('value');

  @override
  List<Field<Object?>> get columns => [name, value];

  @override
  Setting read(Reader row) => Setting(row(name), row(value));

  @override
  List<Assignment> write(Setting setting) => [name.to(setting.name), value.to(setting.value)];
}

/// Declares the column an isolated table reserves.
final class Reserved extends TypedTable<int> {
  Reserved() : super('reserved');

  late final tenant = column.text('__tenant');

  @override
  Tunnel get tunnel => Tunnel.isolated;

  @override
  List<Field<Object?>> get columns => [tenant];

  @override
  int read(Reader row) => 0;

  @override
  List<Assignment> write(int value) => [];
}

/// A shared table pointing at an isolated one, which no tenant could honour.
final class SharedPointer extends TypedTable<int> {
  SharedPointer(this.notes) : super('shared_pointer');

  final Notes notes;

  late final noteId = column.integer('note_id').references(notes.id);

  @override
  List<Field<Object?>> get columns => [noteId];

  @override
  int read(Reader row) => row(noteId);

  @override
  List<Assignment> write(int value) => [noteId.to(value)];
}

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
  late Profiles profiles;
  late Comments comments;
  late Settings settings;
  late LocalDatabase db;
  late Fingerprint fingerprint;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    Tenant.leave();
    directory = await Directory.systemTemp.createTemp('pylon_tenant_tables');
    databaseFactoryFfi.setDatabasesPath(directory.path);
    fingerprint = Fingerprint.generate();
    notes = Notes();
    profiles = Profiles();
    comments = Comments(notes);
    settings = Settings();
    db = LocalDatabase.declared(
      name: 'tenants.db',
      tables: [notes, profiles, comments, settings],
      fingerprint: fingerprint,
    );
    await db.open();
  });

  tearDown(() async {
    Tenant.leave();
    await db.dispose();
    await directory.delete(recursive: true);
  });

  Future<List<String>> titles([Rows<Note>? rows]) async => [
    for (final note in await (rows ?? notes.on(db).orderBy([notes.id.asc()])).list()) note.title,
  ];

  group('the schema of a tunnel', () {
    test('a shared table gains nothing', () async {
      final columns = await db.listColumns('settings');

      expect(columns.map((c) => c.name), ['name', 'value']);
    });

    test('an isolated table gains a hidden tenant column', () async {
      final columns = await db.listColumns('notes');

      expect(columns.map((c) => c.name), ['id', 'title', '__tenant']);
    });

    test('an auto-numbered key stays alone the primary key', () async {
      final keys = (await db.listColumns('notes')).where((c) => c.primaryKeyPosition > 0);

      expect(keys.map((c) => c.name), ['id']);
    });

    test('a text key becomes unique per tenant, the tenant joining it', () async {
      final keys = (await db.listColumns('profiles')).where((c) => c.primaryKeyPosition > 0);

      expect(keys.map((c) => c.name).toSet(), {'__tenant', 'handle'});
    });

    test('reads none of it back as a difference from what was declared', () async {
      for (final table in <TypedTable<Object>>[notes, profiles, comments, settings]) {
        expect(await db.differences(table.declaration), isEmpty, reason: table.tableName);
      }
    });

    test('an isolated table refuses a column of the reserved name', () {
      expect(() => Reserved().declaration, throwsStateError);
    });

    test('a shared table refuses to point at an isolated one', () {
      expect(() => SharedPointer(notes).declaration, throwsStateError);
    });
  });

  group('the tenant mechanism', () {
    test('keeps two tenants apart on every read', () async {
      Tenant.use('a');
      await notes.on(db).insertAll(const [Note(title: 'a1'), Note(title: 'a2')]);
      Tenant.use('b');
      await notes.on(db).insert(const Note(title: 'b1'));

      expect(await titles(), ['b1']);
      expect(await notes.on(db).count(), 1);
      expect(await notes.on(db).where(notes.title.isEqualTo('a1')).exists(), isFalse);
      expect(await notes.on(db).where(notes.title.isEqualTo('a1')).first(), isNull);
      Tenant.use('a');
      expect(await titles(), ['a1', 'a2']);
    });

    test('never reaches another tenant through a key it knows', () async {
      Tenant.use('a');
      final mine = await notes.on(db).insert(const Note(title: 'mine'));
      Tenant.use('b');

      expect(await notes.on(db).get(mine.id!), isNull);
      expect(await notes.on(db).remove(mine.id!), isFalse);
      expect(await notes.on(db).where(notes.id.isEqualTo(mine.id!)).update([notes.title.to('taken')]), 0);
      expect(await notes.on(db).where(notes.id.isEqualTo(mine.id!)).delete(), 0);
      Tenant.use('a');
      expect((await notes.on(db).get(mine.id!))!.title, 'mine');
    });

    test('an update or a delete with a filter only ever changes the current tenant', () async {
      Tenant.use('a');
      await notes.on(db).insert(const Note(title: 'same'));
      Tenant.use('b');
      await notes.on(db).insert(const Note(title: 'same'));

      await notes.on(db).where(notes.title.isEqualTo('same')).update([notes.title.to('changed')]);
      expect(await titles(), ['changed']);
      Tenant.use('a');
      expect(await titles(), ['same']);

      await notes.on(db).deleteAll();
      Tenant.use('b');
      expect(await titles(), ['changed']);
    });

    test('lets two tenants use the same text key, and the same unique value', () async {
      Tenant.use('a');
      await profiles.on(db).insert(const Profile('ada', 'ada@x.dev'));
      Tenant.use('b');
      await profiles.on(db).insert(const Profile('ada', 'ada@x.dev'));
      await profiles.on(db).upsert(const Profile('ada', 'ada@y.dev'));

      expect((await profiles.on(db).get('ada'))!.email, 'ada@y.dev');
      Tenant.use('a');
      expect((await profiles.on(db).get('ada'))!.email, 'ada@x.dev');
    });

    test('still refuses a duplicate key or unique value inside one tenant', () async {
      Tenant.use('a');
      await profiles.on(db).insert(const Profile('ada', 'ada@x.dev'));

      await expectLater(
        profiles.on(db).insert(const Profile('ada', 'other@x.dev')),
        throwsA(isA<UniqueConstraintError>()),
      );
      await expectLater(
        profiles.on(db).insert(const Profile('bob', 'ada@x.dev')),
        throwsA(isA<UniqueConstraintError>()),
      );
    });

    test('holds the anonymous rows apart, and never gives an account back after leaving it', () async {
      Tenant.use('a');
      await notes.on(db).insert(const Note(title: 'account'));

      Tenant.leave();

      expect(await titles(), isEmpty);
      await notes.on(db).insert(const Note(title: 'guest'));
      expect(await titles(), ['guest']);
      Tenant.use('a');
      expect(await titles(), ['account']);
    });

    test('lets a shared table ignore the tenant', () async {
      Tenant.use('a');
      await settings.on(db).insert(const Setting('theme', 'dark'));
      Tenant.use('b');

      expect((await settings.on(db).get('theme'))!.value, 'dark');
      await settings.on(db).upsert(const Setting('theme', 'light'));
      Tenant.use('a');
      expect((await settings.on(db).get('theme'))!.value, 'light');
    });

    test('finishes an operation on the tenant it started on', () async {
      Tenant.use('a');
      final pending = notes.on(db).insert(const Note(title: 'started as a'));
      Tenant.use('b');
      await pending;

      expect(await titles(), isEmpty);
      Tenant.use('a');
      expect(await titles(), ['started as a']);
    });

    test('runs an upsert on the tenant it started on', () async {
      Tenant.use('a');
      final pending = profiles.on(db).upsert(const Profile('ada', 'a@x.dev'));
      Tenant.use('b');
      await pending;

      expect(await profiles.on(db).get('ada'), isNull);
      Tenant.use('a');
      expect((await profiles.on(db).get('ada'))!.email, 'a@x.dev');
    });

    test('reads the tenant at each call inside a transaction', () async {
      Tenant.use('a');
      await db.runTransaction((txn) async {
        await notes.on(txn).insert(const Note(title: 'in a'));
        Tenant.use('b');
        await notes.on(txn).insert(const Note(title: 'in b'));
      });

      expect(await titles(), ['in b']);
      Tenant.use('a');
      expect(await titles(), ['in a']);
    });

    test('refuses an empty tenant id', () {
      expect(() => Tenant.use(''), throwsArgumentError);
    });

    test('reports its changes', () async {
      final seen = <String?>[];
      final subscription = Tenant.changes.listen(seen.add);

      Tenant.use('a');
      Tenant.use('a');
      Tenant.leave();
      Tenant.leave();
      await _settle();
      await subscription.cancel();

      expect(seen, ['a', null]);
    });
  });

  group('foreign keys between isolated tables', () {
    test('a comment points at a note of its own tenant', () async {
      Tenant.use('a');
      final note = await notes.on(db).insert(const Note(title: 'n'));

      final comment = await comments.on(db).insert(Comment(noteId: note.id!, text: 'hi'));

      expect(comment.text, 'hi');
    });

    test('a comment cannot point at another tenant\'s note', () async {
      Tenant.use('a');
      final note = await notes.on(db).insert(const Note(title: 'n'));
      Tenant.use('b');

      await expectLater(
        comments.on(db).insert(Comment(noteId: note.id!, text: 'sneaky')),
        throwsA(isA<ForeignKeyConstraintError>()),
      );
    });

    test('a note cannot be deleted while its own comments point at it', () async {
      Tenant.use('a');
      final note = await notes.on(db).insert(const Note(title: 'n'));
      await comments.on(db).insert(Comment(noteId: note.id!, text: 'hi'));

      await expectLater(notes.on(db).remove(note.id!), throwsA(isA<ForeignKeyConstraintError>()));
    });
  });

  group('the whole-database mechanism', () {
    setUp(() async {
      Tenant.use('a');
      await notes.on(db).insertAll(const [Note(title: 'a1'), Note(title: 'a2')]);
      Tenant.use('b');
      await notes.on(db).insert(const Note(title: 'b1'));
      Tenant.leave();
      await notes.on(db).insert(const Note(title: 'guest'));
    });

    test('reads every tenant, and the anonymous rows', () async {
      final rows = await notes.onWholeDatabase(db, fingerprint).orderBy([notes.id.asc()]).list();

      expect(rows.map((n) => n.title), ['a1', 'a2', 'b1', 'guest']);
      expect(await notes.onWholeDatabase(db, fingerprint).count(), 4);
    });

    test('says whose each row is', () async {
      final rows = await notes.onWholeDatabase(db, fingerprint).orderBy([notes.id.asc()]).listWithTenants();

      expect(rows.map((r) => (r.tenant, r.record.title)), [('a', 'a1'), ('a', 'a2'), ('b', 'b1'), (null, 'guest')]);
    });

    test('filters and narrows to some tenants', () async {
      final only = notes.onWholeDatabase(db, fingerprint).ofTenants(['a', 'b']).orderBy([notes.id.asc()]);

      expect((await only.list()).map((n) => n.title), ['a1', 'a2', 'b1']);
      expect(await notes.onWholeDatabase(db, fingerprint).where(notes.title.isEqualTo('b1')).count(), 1);
      expect(() => notes.onWholeDatabase(db, fingerprint).ofTenants([]), throwsArgumentError);
    });

    test('brings back the same key once per tenant', () async {
      Tenant.use('a');
      await profiles.on(db).insert(const Profile('ada', 'a@x.dev'));
      Tenant.use('b');
      await profiles.on(db).insert(const Profile('ada', 'b@x.dev'));

      final rows = await profiles.onWholeDatabase(db, fingerprint).orderBy([profiles.handle.asc()]).listWithTenants();

      expect(rows.map((r) => (r.tenant, r.record.email)), [('a', 'a@x.dev'), ('b', 'b@x.dev')]);
    });

    test('edits and removes what a filter keeps, wherever it belongs', () async {
      await notes.onWholeDatabase(db, fingerprint).where(notes.title.isEqualTo('a1')).update([notes.title.to('A1')]);
      await notes.onWholeDatabase(db, fingerprint).where(notes.title.isEqualTo('b1')).delete();

      expect((await notes.onWholeDatabase(db, fingerprint).orderBy([notes.id.asc()]).list()).map((n) => n.title), [
        'A1',
        'a2',
        'guest',
      ]);
    });

    test('is simply all of a shared table', () async {
      await settings.on(db).insert(const Setting('theme', 'dark'));

      final rows = await settings.onWholeDatabase(db, fingerprint).listWithTenants();

      expect(rows.map((r) => (r.tenant, r.record.name)), [(null, 'theme')]);
    });

    test('lists the tenants that hold rows, not the anonymous ones', () async {
      expect(await db.wholeDatabase(fingerprint).tenants(), ['a', 'b']);
    });

    test('removes one tenant from every isolated table and nothing else', () async {
      await settings.on(db).insert(const Setting('theme', 'dark'));

      await db.wholeDatabase(fingerprint).purge('a');

      expect(await db.wholeDatabase(fingerprint).tenants(), ['b']);
      expect(await notes.onWholeDatabase(db, fingerprint).count(), 2);
      expect(await settings.on(db).count(), 1);
    });

    test('moves the rows of one tenant to another, counting them', () async {
      final moved = await db.wholeDatabase(fingerprint).transfer(from: 'a', to: 'c');

      expect(moved, 2);
      expect(await db.wholeDatabase(fingerprint).tenants(), ['b', 'c']);
      Tenant.use('c');
      expect(await titles(), ['a1', 'a2']);
    });

    test('keeps the target\'s row on a conflict by default, and lets the source win on request', () async {
      Tenant.use('a');
      await profiles.on(db).insert(const Profile('ada', 'a@x.dev'));
      Tenant.use('b');
      await profiles.on(db).insert(const Profile('ada', 'b@x.dev'));

      await db.wholeDatabase(fingerprint).transfer(from: 'b', to: 'a');
      Tenant.use('a');
      expect((await profiles.on(db).get('ada'))!.email, 'a@x.dev');

      Tenant.use('b');
      await profiles.on(db).insert(const Profile('ada', 'b2@x.dev'));
      await db.wholeDatabase(fingerprint).transfer(from: 'b', to: 'a', onConflict: TransferConflict.keepSource);
      Tenant.use('a');
      expect((await profiles.on(db).get('ada'))!.email, 'b2@x.dev');
    });

    test('moves a note and the comments that point at it together', () async {
      Tenant.use('a');
      final note = (await notes.on(db).list()).first;
      await comments.on(db).insert(Comment(noteId: note.id!, text: 'hi'));

      await db.wholeDatabase(fingerprint).transfer(from: 'a', to: 'c');

      Tenant.use('c');
      expect((await comments.on(db).list()).single.noteId, note.id);
    });

    test('refuses to move a tenant onto itself, or an empty id', () async {
      await expectLater(() => db.wholeDatabase(fingerprint).transfer(from: 'a', to: 'a'), throwsArgumentError);
      await expectLater(() => db.wholeDatabase(fingerprint).transfer(), throwsArgumentError);
      await expectLater(() => db.wholeDatabase(fingerprint).purge(''), throwsArgumentError);
    });
  });

  group('the fingerprint that opens the whole database', () {
    test('is refused when the database was opened without one', () async {
      final bare = LocalDatabase.declared(name: 'bare.db', tables: [notes]);
      await bare.open();

      expect(() => notes.onWholeDatabase(bare, fingerprint), throwsStateError);
      expect(() => bare.wholeDatabase(fingerprint), throwsStateError);
      await bare.dispose();
    });

    test('is refused when it is not the one the database was opened with', () {
      final other = Fingerprint.generate();

      expect(() => notes.onWholeDatabase(db, other), throwsStateError);
      expect(() => db.wholeDatabase(other), throwsStateError);
    });

    test('is needed for the tenant mechanism\'s own reads not at all', () async {
      Tenant.use('a');

      expect(await notes.on(db).count(), 0);
    });
  });

  group('what stays inside the tenant mechanism', () {
    test('adopts the anonymous rows into the current tenant', () async {
      await notes.on(db).insert(const Note(title: 'guest'));
      Tenant.use('a');
      await notes.on(db).insert(const Note(title: 'mine'));

      final moved = await db.adoptAnonymousRows();

      expect(moved, 1);
      expect(await titles(), ['guest', 'mine']);
      Tenant.leave();
      expect(await titles(), isEmpty);
    });

    test('never touches another tenant while adopting', () async {
      Tenant.use('b');
      await notes.on(db).insert(const Note(title: 'b'));
      Tenant.leave();
      await notes.on(db).insert(const Note(title: 'guest'));

      Tenant.use('a');
      await db.adoptAnonymousRows();

      Tenant.use('b');
      expect(await titles(), ['b']);
    });

    test('purges only the current tenant', () async {
      Tenant.use('a');
      await notes.on(db).insert(const Note(title: 'a'));
      Tenant.use('b');
      await notes.on(db).insert(const Note(title: 'b'));

      await db.purgeCurrentTenant();

      expect(await titles(), isEmpty);
      Tenant.use('a');
      expect(await titles(), ['a']);
    });

    test('both need a current tenant', () async {
      await expectLater(() => db.adoptAnonymousRows(), throwsStateError);
      await expectLater(() => db.purgeCurrentTenant(), throwsStateError);
    });
  });

  group('watching with tenants', () {
    test('is handed the new tenant\'s rows from scratch', () async {
      Tenant.use('a');
      await notes.on(db).insert(const Note(title: 'a'));
      Tenant.use('b');
      await notes.on(db).insert(const Note(title: 'b'));
      Tenant.use('a');
      final events = <List<String>>[];
      final subscription = notes.on(db).watch().listen((rows) => events.add([for (final n in rows) n.title]));
      await _waitFor(events, 1);

      Tenant.use('b');
      await _waitFor(events, 2);
      await subscription.cancel();

      expect(events, [
        ['a'],
        ['b'],
      ]);
    });

    test('sends again on a change of tenant even when the rows are the same', () async {
      final events = <int>[];
      Tenant.use('a');
      final subscription = notes.on(db).watch().listen((rows) => events.add(rows.length));
      await _waitFor(events, 1);

      Tenant.use('b');
      await _waitFor(events, 2);
      await subscription.cancel();

      expect(events, [0, 0]);
    });

    test('follows a count too', () async {
      Tenant.use('a');
      await notes.on(db).insert(const Note(title: 'a'));
      final events = <int>[];
      final subscription = notes.on(db).watchCount().listen(events.add);
      await _waitFor(events, 1);

      Tenant.use('b');
      await _waitFor(events, 2);
      await subscription.cancel();

      expect(events, [1, 0]);
    });

    test('a write by another tenant sends nothing to this one', () async {
      Tenant.use('a');
      final events = <int>[];
      final subscription = notes.on(db).watch().listen((rows) => events.add(rows.length));
      await _waitFor(events, 1);

      await db.runTransaction((txn) async {
        Tenant.use('b');
        await notes.on(txn).insert(const Note(title: 'b'));
      });
      await _settle();
      await subscription.cancel();

      expect(events.first, 0);
    });

    test('a shared table ignores a change of tenant', () async {
      await settings.on(db).insert(const Setting('theme', 'dark'));
      final events = <int>[];
      final subscription = settings.on(db).watch().listen((rows) => events.add(rows.length));
      await _waitFor(events, 1);

      Tenant.use('a');
      await _settle();
      await subscription.cancel();

      expect(events, [1]);
    });

    test('the whole-database mechanism sees every tenant\'s writes and ignores a change of tenant', () async {
      final events = <int>[];
      final subscription = notes.onWholeDatabase(db, fingerprint).watch().listen((rows) => events.add(rows.length));
      await _waitFor(events, 1);

      Tenant.use('a');
      await notes.on(db).insert(const Note(title: 'a'));
      await _waitFor(events, 2);
      Tenant.use('b');
      await notes.on(db).insert(const Note(title: 'b'));
      await _waitFor(events, 3);
      await subscription.cancel();

      expect(events, [0, 1, 2]);
    });

    test('a purge and a transfer are heard', () async {
      Tenant.use('a');
      await notes.on(db).insert(const Note(title: 'a'));
      final events = <int>[];
      final subscription = notes.on(db).watch().listen((rows) => events.add(rows.length));
      await _waitFor(events, 1);

      await db.purgeCurrentTenant();
      await _waitFor(events, 2);
      await subscription.cancel();

      expect(events, [1, 0]);
    });
  });
}
