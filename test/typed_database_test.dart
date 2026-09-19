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
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:fiber_pylon/src/sdk/clients/local/database/engine/database.dart';
import 'package:fiber_pylon/src/sdk/clients/local/database/engine/schema/schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';
import 'package:uuid/uuid.dart';

enum Kind { note, task, event }

final class Item extends Equatable {
  const Item({this.id, required this.title, this.done = false, this.due, this.rank = 0});

  final int? id;
  final String title;
  final bool done;
  final Date? due;
  final int rank;

  @override
  List<Object?> get props => [id, title, done, due, rank];
}

final class Items extends DatabaseKeyedTable<Item, int> {
  Items() : super('items');

  late final id = column.key();
  late final title = column.text('title');
  late final done = column.boolean('done').defaultsTo(false);
  late final due = column.date('due').nullable();
  late final rank = column.integer('rank').defaultsTo(0);

  @override
  List<DatabaseField<Object?>> get columns => [id, title, done, due, rank];

  @override
  Item read(DatabaseReader row) =>
      Item(id: row(id), title: row(title), done: row(done), due: row(due), rank: row(rank));

  @override
  List<DatabaseAssignment> write(Item item) => [
    id.toOrGenerate(item.id),
    title.to(item.title),
    done.to(item.done),
    due.to(item.due),
    rank.to(item.rank),
  ];
}

final class Label extends Equatable {
  const Label({this.id, required this.name});

  final UuidValue? id;
  final String name;

  @override
  List<Object?> get props => [id, name];
}

final class Labels extends DatabaseKeyedTable<Label, UuidValue> {
  Labels() : super('labels');

  late final id = column.uuidKey();
  late final name = column.text('name').unique();

  @override
  List<DatabaseField<Object?>> get columns => [id, name];

  @override
  Label read(DatabaseReader row) => Label(id: row(id), name: row(name));

  @override
  List<DatabaseAssignment> write(Label label) => [id.toOrGenerate(label.id), name.to(label.name)];
}

final class Link {
  const Link({required this.itemId, required this.labelId});

  final int itemId;
  final UuidValue labelId;
}

final class Links extends DatabaseTable<Link> {
  Links() : super('links');

  late final itemId = column.integer('item_id').references(items.id, onDelete: ReferentialAction.cascade);
  late final labelId = column.uuid('label_id').references(labels.id, onDelete: ReferentialAction.cascade);

  @override
  List<DatabaseField<Object?>> get columns => [itemId, labelId];

  @override
  List<DatabaseField<Object?>> get primaryKey => [itemId, labelId];

  @override
  List<List<DatabaseField<Object?>>> get indexes => [
    [labelId],
  ];

  @override
  Link read(DatabaseReader row) => Link(itemId: row(itemId), labelId: row(labelId));

  @override
  List<DatabaseAssignment> write(Link link) => [itemId.to(link.itemId), labelId.to(link.labelId)];
}

final class Sample extends Equatable {
  const Sample({
    this.id,
    required this.kind,
    required this.ratio,
    required this.at,
    required this.day,
    required this.clock,
    required this.tags,
    required this.blob,
    required this.detail,
    this.note,
  });

  final int? id;
  final Kind kind;
  final double ratio;
  final DateTime at;
  final Date day;
  final Time clock;
  final List<String> tags;
  final Uint8List blob;
  final Detail detail;
  final String? note;

  @override
  List<Object?> get props => [id, kind, ratio, at, day, clock, tags, blob, detail, note];
}

final class Detail extends Equatable {
  const Detail(this.size);

  final int size;

  static Detail fromJson(Map<String, dynamic> json) => Detail(json['size'] as int);

  Map<String, dynamic> toJson() => {'size': size};

  @override
  List<Object?> get props => [size];
}

Map<String, dynamic> _detailToJson(Detail detail) => detail.toJson();

final class Samples extends DatabaseKeyedTable<Sample, int> {
  Samples() : super('samples');

  late final id = column.key();
  late final kind = column.enumeration('kind', Kind.values);
  late final ratio = column.real('ratio');
  late final at = column.timestamp('at');
  late final day = column.date('day');
  late final clock = column.time('clock');
  late final tags = column.list<String>('tags');
  late final blob = column.blob('blob');
  late final detail = column.json('detail', const Json<Detail>(fromJson: Detail.fromJson, toJson: _detailToJson));
  late final note = column.text('note').nullable();

  @override
  List<DatabaseField<Object?>> get columns => [id, kind, ratio, at, day, clock, tags, blob, detail, note];

  @override
  Sample read(DatabaseReader row) => Sample(
    id: row(id),
    kind: row(kind),
    ratio: row(ratio),
    at: row(at),
    day: row(day),
    clock: row(clock),
    tags: row(tags),
    blob: row(blob),
    detail: row(detail),
    note: row(note),
  );

  @override
  List<DatabaseAssignment> write(Sample sample) => [
    id.toOrGenerate(sample.id),
    kind.to(sample.kind),
    ratio.to(sample.ratio),
    at.to(sample.at),
    day.to(sample.day),
    clock.to(sample.clock),
    tags.to(sample.tags),
    blob.to(sample.blob),
    detail.to(sample.detail),
    note.to(sample.note),
  ];
}

final class Reserved extends DatabaseKeyedTable<String, int> {
  Reserved() : super('order');

  late final id = column.key();
  late final group = column.text('group');

  @override
  List<DatabaseField<Object?>> get columns => [id, group];

  @override
  String read(DatabaseReader row) => row(group);

  @override
  List<DatabaseAssignment> write(String record) => [id.toOrGenerate(null), group.to(record)];
}

final class Forgetful extends DatabaseTable<String> {
  Forgetful() : super('forgetful');

  late final kept = column.text('kept');
  late final lost = column.text('lost');

  @override
  List<DatabaseField<Object?>> get columns => [kept];

  @override
  String read(DatabaseReader row) => row(kept);

  @override
  List<DatabaseAssignment> write(String record) => [kept.to(record), lost.to(record)];
}

final class WrongKey extends DatabaseKeyedTable<String, String> {
  WrongKey() : super('wrong_key');

  late final id = column.key();

  @override
  List<DatabaseField<Object?>> get columns => [id];

  @override
  String read(DatabaseReader row) => '${row(id)}';

  @override
  List<DatabaseAssignment> write(String record) => [id.toOrGenerate(null)];
}

final class ItemsV2 extends DatabaseTable<String> {
  ItemsV2({required this.gainedColumn}) : super('items');

  final DatabaseField<Object?> Function(DatabaseColumns column) gainedColumn;

  late final title = column.text('title');
  late final gained = gainedColumn(column);

  @override
  List<DatabaseField<Object?>> get columns => [title, gained];

  @override
  String read(DatabaseReader row) => row(title);

  @override
  List<DatabaseAssignment> write(String record) => [title.to(record)];
}

final class People extends DatabaseTable<String> {
  People() : super('people');

  late final name = column.text('name').unique().collatedBy(Collation.noCase);

  @override
  List<DatabaseField<Object?>> get columns => [name];

  @override
  String read(DatabaseReader row) => row(name);

  @override
  List<DatabaseAssignment> write(String record) => [name.to(record)];
}

final class Money extends Equatable {
  const Money(this.cents);

  final int cents;

  @override
  List<Object?> get props => [cents];
}

final class Price {
  const Price(this.amount);

  final Money amount;
}

final class Prices extends DatabaseTable<Price> {
  Prices() : super('prices');

  late final amount = column.custom(
    'amount',
    DatabaseCodec<Money>(
      storage: ColumnType.integer,
      encode: (money) => DatabaseType.integer(money.cents),
      decode: (stored) => Money(stored.asInt),
    ),
  );

  @override
  List<DatabaseField<Object?>> get columns => [amount];

  @override
  Price read(DatabaseReader row) => Price(row(amount));

  @override
  List<DatabaseAssignment> write(Price price) => [amount.to(price.amount)];
}

final class Setting extends Equatable {
  const Setting(this.key, this.value);

  final String key;
  final String value;

  @override
  List<Object?> get props => [key, value];
}

final class Settings extends DatabaseKeyedTable<Setting, String> {
  Settings() : super('settings');

  late final key = column.text('key').primaryKey();
  late final value = column.text('value');

  @override
  List<DatabaseField<Object?>> get columns => [key, value];

  @override
  Setting read(DatabaseReader row) => Setting(row(key), row(value));

  @override
  List<DatabaseAssignment> write(Setting setting) => [key.to(setting.key), value.to(setting.value)];
}

final class Bare extends DatabaseKeyedTable<int, int> {
  Bare() : super('bare');

  late final id = column.key();

  @override
  List<DatabaseField<Object?>> get columns => [id];

  @override
  int read(DatabaseReader row) => row(id);

  @override
  List<DatabaseAssignment> write(int record) => [id.toOrGenerate(null)];
}

final items = Items();
final prices = Prices();
final settings = Settings();
final bare = Bare();
final people = People();
final labels = Labels();
final links = Links();
final samples = Samples();
final reserved = Reserved();

LocalDatabase _openable(String name) =>
    LocalDatabase.declared(name: name, tables: [items, labels, links, samples, people, prices, settings, bare]);

Future<LocalDatabase> _open(String name) async {
  final db = _openable(name);
  await db.open();
  return db;
}

Future<List<String>> _columnNames(LocalDatabase db, String table) async => [
  for (final column in await db.columns(table)) column.name,
];

void main() {
  late Directory directory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pylon_typed_database');
    databaseFactoryFfi.setDatabasesPath(directory.path);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  group('LocalDatabase.declared', () {
    test('creates every declared table with no callback and stores the schema version', () async {
      final db = await _open('declared.db');

      expect(await db.tableNames(), containsAll(['items', 'labels', 'links', 'samples']));
      expect(await _columnNames(db, 'items'), ['id', 'title', 'done', 'due', 'rank']);
      final version = await db.rawQuery('PRAGMA user_version');
      expect(version.single['user_version']!.asInt, 1);
      await db.dispose();
    });

    test('enforces foreign keys without the developer setting the pragma', () async {
      final db = await _open('foreign_keys.db');

      await expectLater(
        links.on(db).insert(Link(itemId: 99, labelId: UuidValue.fromString('11111111-1111-4111-8111-111111111111'))),
        throwsA(isA<DatabaseError>()),
      );
      await db.dispose();
    });

    test('opens the journal in write-ahead mode', () async {
      final db = await _open('journal.db');

      final rows = await db.rawQuery('PRAGMA journal_mode');

      expect(rows.single['journal_mode']!.asString, 'wal');
      await db.dispose();
    });

    test('adds a nullable column a newer declaration gained, with no migration code', () async {
      final older = LocalDatabase.declared(
        name: 'gain.db',
        tables: [ItemsV2(gainedColumn: (c) => c.text('a'))],
      );
      await older.open();
      await older.dispose();
      final newer = LocalDatabase.declared(
        name: 'gain.db',
        tables: [ItemsV2(gainedColumn: (c) => c.date('due').nullable())],
      );

      await newer.open();

      expect(await _columnNames(newer, 'items'), containsAll(['title', 'a', 'due']));
      await newer.dispose();
    });

    test('gives an existing row the default of a column added later', () async {
      final older = LocalDatabase.declared(
        name: 'backfill.db',
        tables: [ItemsV2(gainedColumn: (c) => c.text('a').nullable())],
      );
      await older.open();
      await older.execute('INSERT INTO items (title) VALUES (?)', const [DatabaseType.varchar('old')]);
      await older.dispose();
      final newer = LocalDatabase.declared(
        name: 'backfill.db',
        tables: [ItemsV2(gainedColumn: (c) => c.integer('rank').defaultsTo(3))],
      );
      await newer.open();

      final rows = await newer.rawQuery('SELECT rank FROM items');

      expect(rows.single['rank']!.asInt, 3);
      await newer.dispose();
    });

    test('refuses a column that refuses NULL and has no default, naming it', () async {
      final older = LocalDatabase.declared(
        name: 'refuse.db',
        tables: [ItemsV2(gainedColumn: (c) => c.text('a'))],
      );
      await older.open();
      await older.dispose();
      final newer = LocalDatabase.declared(
        name: 'refuse.db',
        tables: [ItemsV2(gainedColumn: (c) => c.integer('rank'))],
      );

      await expectLater(
        newer.open(),
        throwsA(
          isA<DatabaseMigrationRequiredError>().having((error) => error.message, 'message', contains('items.rank')),
        ),
      );
      expect(newer.isOpen, isFalse);
    });

    test('runs a migration for a file of an older version and stores the new version', () async {
      final v1 = LocalDatabase.declared(name: 'migrate.db', tables: [items]);
      await v1.open();
      await items.on(v1).insert(const Item(title: 'kept'));
      await v1.dispose();
      final seen = <String>[];
      final v2 = LocalDatabase.declared(
        name: 'migrate.db',
        tables: [items],
        migrations: [
          (txn) async {
            seen.add('ran');
            await txn.execute("UPDATE items SET title = 'migrated'");
          },
        ],
      );

      await v2.open();

      expect(seen, ['ran']);
      expect((await items.on(v2).list()).single.title, 'migrated');
      final version = await v2.rawQuery('PRAGMA user_version');
      expect(version.single['user_version']!.asInt, 2);
      await v2.dispose();
    });

    test('runs no migration on a fresh file and starts it at the latest version', () async {
      final seen = <String>[];
      final db = LocalDatabase.declared(
        name: 'fresh_migrate.db',
        tables: [items],
        migrations: [(txn) async => seen.add('ran'), (txn) async => seen.add('ran')],
      );

      await db.open();

      expect(seen, isEmpty);
      final version = await db.rawQuery('PRAGMA user_version');
      expect(version.single['user_version']!.asInt, 3);
      await db.dispose();
    });

    test('runs the migrations in order, skipping the ones a file already went through', () async {
      final seen = <int>[];
      final tables = [items];
      final v2 = LocalDatabase.declared(name: 'ordered.db', tables: tables, migrations: [(txn) async => seen.add(2)]);
      await v2.open();
      await v2.dispose();
      final v4 = LocalDatabase.declared(
        name: 'ordered.db',
        tables: tables,
        migrations: [(txn) async => seen.add(2), (txn) async => seen.add(3), (txn) async => seen.add(4)],
      );

      await v4.open();

      expect(seen, [3, 4]);
      await v4.dispose();
    });

    test('rolls the whole upgrade back when a migration throws, leaving the file at its old version', () async {
      final v1 = LocalDatabase.declared(name: 'rollback.db', tables: [items]);
      await v1.open();
      await v1.dispose();
      final broken = LocalDatabase.declared(
        name: 'rollback.db',
        tables: [items],
        migrations: [
          (txn) async {
            await txn.execute('CREATE TABLE half_done (id INTEGER)');
            throw StateError('stop');
          },
        ],
      );

      await expectLater(broken.open(), throwsStateError);

      final again = LocalDatabase.declared(name: 'rollback.db', tables: [items]);
      await again.open();
      expect(await again.tableExists('half_done'), isFalse);
      final version = await again.rawQuery('PRAGMA user_version');
      expect(version.single['user_version']!.asInt, 1);
      await again.dispose();
    });

    test('refuses a file written by a newer schema version instead of reading it wrongly', () async {
      final newer = LocalDatabase.declared(name: 'too_new.db', tables: [items], migrations: [(txn) async {}]);
      await newer.open();
      await newer.dispose();
      final older = LocalDatabase.declared(name: 'too_new.db', tables: [items]);

      await expectLater(older.open(), throwsA(isA<DatabaseSchemaTooNewError>()));
      expect(older.isOpen, isFalse);
    });

    test('adopts a file that carries tables but no version as version 1', () async {
      final plain = LocalDatabase(
        name: 'adopt.db',
        onCreate: (db, version) => db.execute('CREATE TABLE things (id INTEGER)'),
      );
      await plain.open();
      await plain.dispose();
      final seen = <String>[];
      final db = LocalDatabase.declared(
        name: 'adopt.db',
        tables: [items],
        migrations: [(txn) async => seen.add('ran')],
      );

      await db.open();

      expect(seen, ['ran']);
      await db.dispose();
    });

    test('creates a declared index once and adds one the file lacks', () async {
      final db = await _open('index.db');
      await db.dispose();
      final again = await _open('index.db');

      final rows = await again.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'links_label_id_idx'",
      );

      expect(rows, hasLength(1));
      await again.dispose();
    });

    test('creates the tables passed as untyped declarations too', () async {
      final db = LocalDatabase.declared(
        name: 'untyped.db',
        tables: [items],
        declarations: [
          TableBuilder('audit').columns((c) => {'entry': c.text()}),
        ],
      );

      await db.open();

      expect(await db.tableNames(), containsAll(['items', 'audit']));
      await db.dispose();
    });

    test('opens a file read only with no schema work, so a newer declaration adds nothing', () async {
      final older = LocalDatabase.declared(
        name: 'read_only.db',
        tables: [ItemsV2(gainedColumn: (c) => c.text('a'))],
      );
      await older.open();
      await older.dispose();
      final reader = LocalDatabase.declared(
        name: 'read_only.db',
        tables: [ItemsV2(gainedColumn: (c) => c.date('due').nullable())],
        readOnly: true,
      );

      await reader.open();

      expect(await _columnNames(reader, 'items'), ['title', 'a']);
      await reader.dispose();
    });

    test('refuses a table that was not declared to this database', () async {
      final db = await _open('undeclared.db');

      expect(() => reserved.on(db), throwsStateError);
      await db.dispose();
    });

    test('refuses a table that lists a column it never declared to the schema', () async {
      final db = LocalDatabase.declared(name: 'forgetful.db', tables: [Forgetful()]);
      await db.open();

      await expectLater(
        Forgetful().on(db).insert('x'),
        throwsA(isA<StateError>().having((error) => error.message, 'message', contains('forgetful.lost'))),
      );
      await db.dispose();
    });

    test('refuses a keyed table whose key type differs from the type it declares', () async {
      final db = LocalDatabase.declared(name: 'wrong_key.db', tables: [WrongKey()]);

      await expectLater(db.open(), throwsStateError);
    });

    test('keeps a table and a column named after SQL keywords working', () async {
      final db = LocalDatabase.declared(name: 'keywords.db', tables: [reserved]);
      await db.open();

      await reserved.on(db).insert('x');
      final found = await reserved.on(db).where(reserved.group.isEqualTo('x')).orderBy([reserved.group.desc()]).list();

      expect(found, ['x']);
      await db.dispose();
    });
  });

  group('records', () {
    test('insert answers the record with the key the database numbered', () async {
      final db = await _open('insert.db');

      final first = await items.on(db).insert(const Item(title: 'a'));
      final second = await items.on(db).insert(const Item(title: 'b'));

      expect(first, const Item(id: 1, title: 'a'));
      expect(second.id, 2);
      await db.dispose();
    });

    test('insert answers a UUID key the engine generated when the record had none', () async {
      final db = await _open('uuid_key.db');

      final label = await labels.on(db).insert(const Label(name: 'work'));

      expect(label.id, isNotNull);
      expect(await labels.on(db).get(label.id!), label);
      await db.dispose();
    });

    test('insert keeps a UUID key the record already carries', () async {
      final db = await _open('uuid_kept.db');
      final id = UuidValue.fromString('22222222-2222-4222-8222-222222222222');

      final label = await labels.on(db).insert(Label(id: id, name: 'work'));

      expect(label.id, id);
      await db.dispose();
    });

    test('insert refuses a colliding row instead of replacing it', () async {
      final db = await _open('collide.db');
      await labels.on(db).insert(const Label(name: 'work'));

      await expectLater(labels.on(db).insert(const Label(name: 'work')), throwsA(isA<DatabaseUniqueConstraintError>()));
      await db.dispose();
    });

    test('insertAll answers the records in the order they were given', () async {
      final db = await _open('insert_all.db');

      final saved = await items.on(db).insertAll(const [Item(title: 'c'), Item(title: 'a'), Item(title: 'b')]);

      expect(saved.map((item) => item.title), ['c', 'a', 'b']);
      expect(saved.map((item) => item.id), [1, 2, 3]);
      await db.dispose();
    });

    test('insertAll lands nothing when one record fails', () async {
      final db = await _open('insert_all_rollback.db');

      await expectLater(
        labels.on(db).insertAll(const [Label(name: 'a'), Label(name: 'b'), Label(name: 'a')]),
        throwsA(isA<DatabaseUniqueConstraintError>()),
      );

      expect(await labels.on(db).count(), 0);
      await db.dispose();
    });

    test('insertAll of nothing answers nothing', () async {
      final db = await _open('insert_none.db');

      expect(await items.on(db).insertAll(const []), isEmpty);
      await db.dispose();
    });

    test('get answers null for a key no row holds', () async {
      final db = await _open('get_missing.db');

      expect(await items.on(db).get(7), isNull);
      await db.dispose();
    });

    test('upsert updates the row in place and keeps the rows that point at it', () async {
      final db = await _open('upsert_keeps.db');
      final item = await items.on(db).insert(const Item(title: 'a'));
      final label = await labels.on(db).insert(const Label(name: 'work'));
      await links.on(db).insert(Link(itemId: item.id!, labelId: label.id!));

      final renamed = await labels.on(db).upsert(Label(id: label.id, name: 'renamed'));

      expect(renamed.name, 'renamed');
      expect(await links.on(db).count(), 1);
      await db.dispose();
    });

    test('upsert inserts when no row holds the key, and when the record has no key yet', () async {
      final db = await _open('upsert_inserts.db');

      final created = await items.on(db).upsert(const Item(title: 'a'));
      final placed = await items.on(db).upsert(const Item(id: 50, title: 'b'));

      expect(created.id, 1);
      expect(placed, const Item(id: 50, title: 'b'));
      expect(await items.on(db).count(), 2);
      await db.dispose();
    });

    test('upsert of a record with only its key does not fail', () async {
      final db = await _open('upsert_key_only.db');
      final label = await labels.on(db).insert(const Label(name: 'work'));

      final again = await labels.on(db).upsert(label);

      expect(again, label);
      await db.dispose();
    });

    test('remove answers whether a row was there', () async {
      final db = await _open('remove.db');
      final item = await items.on(db).insert(const Item(title: 'a'));

      expect(await items.on(db).remove(item.id!), isTrue);
      expect(await items.on(db).remove(item.id!), isFalse);
      await db.dispose();
    });

    test('deleting a row cascades to the rows that reference it', () async {
      final db = await _open('cascade.db');
      final item = await items.on(db).insert(const Item(title: 'a'));
      final label = await labels.on(db).insert(const Label(name: 'work'));
      await links.on(db).insert(Link(itemId: item.id!, labelId: label.id!));

      await items.on(db).remove(item.id!);

      expect(await links.on(db).count(), 0);
      await db.dispose();
    });

    test('round trips every column type the columns open', () async {
      final db = LocalDatabase.declared(name: 'codecs.db', tables: [samples]);
      await db.open();
      final sample = Sample(
        kind: Kind.task,
        ratio: 0.25,
        at: DateTime.utc(2026, 3, 4, 5, 6, 7, 8),
        day: const Date(year: 2026, month: 3, day: 4),
        clock: const Time(hour: 9, minute: 30, second: 15, millisecond: 500),
        tags: const ['a', 'b'],
        blob: Uint8List.fromList([0, 1, 255]),
        detail: const Detail(3),
      );

      final saved = await samples.on(db).insert(sample);

      expect(
        saved,
        Sample(
          id: 1,
          kind: sample.kind,
          ratio: sample.ratio,
          at: sample.at,
          day: sample.day,
          clock: sample.clock,
          tags: sample.tags,
          blob: sample.blob,
          detail: sample.detail,
        ),
      );
      await db.dispose();
    });

    test('a column of a type of your own is stored through its codec', () async {
      final db = await _open('custom_codec.db');

      await prices.on(db).insert(const Price(Money(1250)));

      final stored = await db.rawQuery('SELECT amount FROM prices');
      expect(stored.single['amount']!.asInt, 1250);
      expect((await prices.on(db).list()).single.amount, const Money(1250));
      await db.dispose();
    });

    test('a text primary key upserts and reads back by its key', () async {
      final db = await _open('text_key.db');

      await settings.on(db).upsert(const Setting('theme', 'dark'));
      await settings.on(db).upsert(const Setting('theme', 'light'));

      expect(await settings.on(db).get('theme'), const Setting('theme', 'light'));
      expect(await settings.on(db).count(), 1);
      await db.dispose();
    });

    test('a table with only a key inserts a row of defaults', () async {
      final db = await _open('bare.db');

      final first = await bare.on(db).insert(0);
      final second = await bare.on(db).insert(0);

      expect([first, second], [1, 2]);
      await db.dispose();
    });

    test('insertAll of more records than one query holds answers them all in order', () async {
      final db = await _open('insert_many.db');

      final saved = await items.on(db).insertAll([for (var index = 0; index < 1200; index++) Item(title: 't$index')]);

      expect(saved.map((item) => item.title), [for (var index = 0; index < 1200; index++) 't$index']);
      expect(saved.last.id, 1200);
      await db.dispose();
    });

    test('reads NULL as null on a nullable column and writes null back as NULL', () async {
      final db = await _open('nullable.db');
      final saved = await items.on(db).insert(const Item(title: 'a'));

      final dated = await items
          .on(db)
          .upsert(Item(id: saved.id, title: 'a', due: const Date(year: 2026, month: 1, day: 2)));
      final cleared = await items.on(db).upsert(Item(id: saved.id, title: 'a'));

      expect(saved.due, isNull);
      expect(dated.due, const Date(year: 2026, month: 1, day: 2));
      expect(cleared.due, isNull);
      await db.dispose();
    });

    test('reading NULL from a column not declared nullable names the column', () async {
      final db = LocalDatabase.declared(name: 'null_in_required.db', tables: [items]);
      await db.open();
      await db.execute('DROP TABLE items');
      await db.execute(
        'CREATE TABLE items (id INTEGER PRIMARY KEY, title TEXT, done INTEGER, due INTEGER, rank INTEGER)',
      );
      await db.execute('INSERT INTO items DEFAULT VALUES');

      await expectLater(
        items.on(db).list(),
        throwsA(isA<StateError>().having((error) => error.message, 'message', contains('items.title'))),
      );
      await db.dispose();
    });
  });

  group('rows', () {
    Future<LocalDatabase> seeded(String name) async {
      final db = await _open(name);
      await items.on(db).insertAll([
        const Item(title: 'alpha', rank: 1, due: Date(year: 2026, month: 1, day: 10)),
        const Item(title: 'beta', done: true, rank: 2, due: Date(year: 2026, month: 2, day: 10)),
        const Item(title: 'gamma_100%', rank: 3),
        const Item(title: 'delta', done: true, rank: 4, due: Date(year: 2026, month: 3, day: 10)),
      ]);
      return db;
    }

    Future<List<String>> titles(DatabaseRows<Item> rows) async => [for (final item in await rows.list()) item.title];

    test('where keeps the rows a typed filter matches', () async {
      final db = await seeded('where.db');

      expect(await titles(items.on(db).where(items.done.isEqualTo(true))), ['beta', 'delta']);
      expect(await titles(items.on(db).where(items.done.isNotEqualTo(true))), ['alpha', 'gamma_100%']);
      await db.dispose();
    });

    test('where called twice keeps the rows both filters match instead of replacing the first', () async {
      final db = await seeded('where_twice.db');

      final rows = items.on(db).where(items.done.isEqualTo(true)).where(items.rank.isGreaterThan(2));

      expect(await titles(rows), ['delta']);
      await db.dispose();
    });

    test('and, or and not combine filters with operators', () async {
      final db = await seeded('operators.db');

      expect(await titles(items.on(db).where(items.done.isEqualTo(true) | items.rank.isEqualTo(1))), [
        'alpha',
        'beta',
        'delta',
      ]);
      expect(await titles(items.on(db).where(~items.done.isEqualTo(true))), ['alpha', 'gamma_100%']);
      expect(
        await titles(
          items.on(db).where(items.rank.isEqualTo(1) | items.rank.isEqualTo(2) & items.done.isEqualTo(true)),
        ),
        ['alpha', 'beta'],
      );
      await db.dispose();
    });

    test('all and any combine a list of filters assembled at run time', () async {
      final db = await seeded('all_any.db');

      expect(
        await titles(items.on(db).where(DatabaseFilter.all([items.done.isEqualTo(true), items.rank.isLessThan(3)]))),
        ['beta'],
      );
      expect(await titles(items.on(db).where(DatabaseFilter.any([items.rank.isEqualTo(1), items.rank.isEqualTo(4)]))), [
        'alpha',
        'delta',
      ]);
      expect(await items.on(db).where(DatabaseFilter.any(const [])).count(), 0);
      await db.dispose();
    });

    test('ordering filters work on numbers, dates and text, and isBetween includes both ends', () async {
      final db = await seeded('ordering.db');

      expect(await titles(items.on(db).where(items.rank.isGreaterThanOrEqualTo(3))), ['gamma_100%', 'delta']);
      expect(await titles(items.on(db).where(items.due.isLessThan(const Date(year: 2026, month: 2, day: 10)))), [
        'alpha',
      ]);
      expect(
        await titles(
          items
              .on(db)
              .where(
                items.due.isBetween(
                  const Date(year: 2026, month: 1, day: 10),
                  const Date(year: 2026, month: 2, day: 10),
                ),
              ),
        ),
        ['alpha', 'beta'],
      );
      expect(await titles(items.on(db).where(items.title.isGreaterThan('c'))), ['gamma_100%', 'delta']);
      await db.dispose();
    });

    test('isNull and isNotNull read a nullable column', () async {
      final db = await seeded('nulls.db');

      expect(await titles(items.on(db).where(items.due.isNull())), ['gamma_100%']);
      expect(await titles(items.on(db).where(items.due.isNotNull())), ['alpha', 'beta', 'delta']);
      expect(await titles(items.on(db).where(items.due.isEqualTo(null))), ['gamma_100%']);
      await db.dispose();
    });

    test('isNull on a column that refuses NULL is refused instead of matching nothing', () async {
      expect(() => items.title.isNull(), throwsStateError);
      expect(() => items.title.isNotNull(), throwsStateError);
    });

    test('isIn matches a set of values, none for an empty set and NULL rows when given a null', () async {
      final db = await seeded('is_in.db');

      expect(await titles(items.on(db).where(items.rank.isIn([1, 4]))), ['alpha', 'delta']);
      expect(await titles(items.on(db).where(items.rank.isIn(const []))), isEmpty);
      expect(await titles(items.on(db).where(items.due.isIn([null, const Date(year: 2026, month: 1, day: 10)]))), [
        'alpha',
        'gamma_100%',
      ]);
      await db.dispose();
    });

    test('a raw filter combines with typed filters and is not checked against a table', () async {
      final db = await seeded('raw.db');

      final rows = items
          .on(db)
          .where(DatabaseFilter.raw('rank % 2 = ?', const [DatabaseType.integer(0)]) & items.done.isEqualTo(true));

      expect(await titles(rows), ['beta', 'delta']);
      await db.dispose();
    });

    test('contains, startsWith and endsWith read the text as written', () async {
      final db = await seeded('text.db');

      expect(await titles(items.on(db).where(items.title.contains('_100%'))), ['gamma_100%']);
      expect(await titles(items.on(db).where(items.title.contains('%'))), ['gamma_100%']);
      expect(await titles(items.on(db).where(items.title.startsWith('al'))), ['alpha']);
      expect(await titles(items.on(db).where(items.title.endsWith('ta'))), ['beta', 'delta']);
      await db.dispose();
    });

    test('a NOCASE column treats two spellings as one value', () async {
      final db = LocalDatabase.declared(name: 'collation.db', tables: [people]);
      await db.open();
      await people.on(db).insert('Ada');

      await expectLater(people.on(db).insert('ADA'), throwsA(isA<DatabaseUniqueConstraintError>()));
      expect(await people.on(db).where(people.name.startsWith('a')).count(), 1);
      await db.dispose();
    });

    test('orders by several columns, each in its own direction', () async {
      final db = await seeded('order.db');

      expect(await titles(items.on(db).orderBy([items.done.asc(), items.rank.desc()])), [
        'gamma_100%',
        'alpha',
        'delta',
        'beta',
      ]);
      await db.dispose();
    });

    test('limit and offset page the rows, and an offset alone is a valid page', () async {
      final db = await seeded('page.db');
      final ordered = items.on(db).orderBy([items.rank.asc()]);

      expect(await titles(ordered.limit(2).offset(1)), ['beta', 'gamma_100%']);
      expect(await titles(ordered.offset(3)), ['delta']);
      expect(() => ordered.limit(-1), throwsRangeError);
      expect(() => ordered.offset(-1), throwsRangeError);
      await db.dispose();
    });

    test('first, count and exists answer for the rows kept', () async {
      final db = await seeded('terminals.db');
      final done = items.on(db).where(items.done.isEqualTo(true));

      expect((await done.orderBy([items.rank.desc()]).first())?.title, 'delta');
      expect(await done.count(), 2);
      expect(await done.exists(), isTrue);
      expect(await items.on(db).where(items.rank.isEqualTo(99)).exists(), isFalse);
      expect(await items.on(db).where(items.rank.isEqualTo(99)).first(), isNull);
      expect(await items.on(db).count(), 4);
      await db.dispose();
    });

    test('count and exists refuse a page they would silently ignore', () async {
      final db = await seeded('count_page.db');

      await expectLater(items.on(db).limit(1).count(), throwsStateError);
      await expectLater(items.on(db).offset(1).exists(), throwsStateError);
      await db.dispose();
    });

    test('update writes only the columns it is given and answers how many rows changed', () async {
      final db = await seeded('update.db');

      final changed = await items.on(db).where(items.done.isEqualTo(true)).update([items.rank.to(0)]);

      expect(changed, 2);
      expect(await titles(items.on(db).where(items.rank.isEqualTo(0))), ['beta', 'delta']);
      expect((await items.on(db).get(2))?.done, isTrue);
      await db.dispose();
    });

    test('update and delete with no where are refused, and updateAll and deleteAll refuse a where', () async {
      final db = await seeded('no_where.db');

      await expectLater(items.on(db).update([items.rank.to(0)]), throwsStateError);
      await expectLater(items.on(db).delete(), throwsStateError);
      await expectLater(items.on(db).where(items.rank.isEqualTo(1)).updateAll([items.rank.to(0)]), throwsStateError);
      await expectLater(items.on(db).where(items.rank.isEqualTo(1)).deleteAll(), throwsStateError);
      expect(await items.on(db).count(), 4);
      await db.dispose();
    });

    test('updateAll and deleteAll act on every row', () async {
      final db = await seeded('all_rows.db');

      expect(await items.on(db).updateAll([items.rank.to(9)]), 4);
      expect(await items.on(db).where(items.rank.isEqualTo(9)).count(), 4);
      expect(await items.on(db).deleteAll(), 4);
      expect(await items.on(db).count(), 0);
      await db.dispose();
    });

    test('delete removes the rows kept and refuses a limit it would ignore', () async {
      final db = await seeded('delete.db');

      await expectLater(items.on(db).where(items.done.isEqualTo(true)).limit(1).delete(), throwsStateError);
      expect(await items.on(db).where(items.done.isEqualTo(true)).delete(), 2);
      expect(await items.on(db).count(), 2);
      await db.dispose();
    });

    test('update with nothing to set is refused', () async {
      final db = await seeded('empty_set.db');

      await expectLater(items.on(db).where(items.rank.isEqualTo(1)).update(const []), throwsStateError);
      await db.dispose();
    });

    test('a filter built from a column of another table is refused, whether direct or combined', () async {
      final db = await seeded('foreign_filter.db');

      expect(() => items.on(db).where(labels.name.isEqualTo('x')), throwsArgumentError);
      expect(() => items.on(db).where(items.rank.isEqualTo(1) & labels.name.isEqualTo('x')), throwsArgumentError);
      expect(() => items.on(db).where(~labels.name.isEqualTo('x')), throwsArgumentError);
      await db.dispose();
    });

    test('a subquery whose filter reads another table is refused', () async {
      expect(() => links.itemId.where(labels.name.isEqualTo('x')), throwsArgumentError);
    });

    test('isInSelect finds the rows a link table points at, across a many to many', () async {
      final db = await seeded('many_to_many.db');
      final work = await labels.on(db).insert(const Label(name: 'work'));
      final home = await labels.on(db).insert(const Label(name: 'home'));
      await links.on(db).insertAll([
        Link(itemId: 1, labelId: work.id!),
        Link(itemId: 2, labelId: work.id!),
        Link(itemId: 2, labelId: home.id!),
      ]);

      final tagged = items
          .on(db)
          .where(
            items.id.isInSelect(
              links.itemId.where(links.labelId.isInSelect(labels.id.where(labels.name.isEqualTo('work')))),
            ),
          );

      expect(await titles(tagged), ['alpha', 'beta']);
      expect(
        await titles(items.on(db).where(~items.id.isInSelect(links.itemId.where(links.labelId.isEqualTo(home.id!))))),
        ['alpha', 'gamma_100%', 'delta'],
      );
      await db.dispose();
    });

    test('reading a column of another table through a row is refused', () async {
      final table = _ForeignRead();
      final probe = LocalDatabase.declared(name: 'foreign_read_probe.db', tables: [table]);
      await probe.open();

      await expectLater(table.on(probe).insert('x'), throwsStateError);
      await probe.dispose();
    });
  });

  group('transactions', () {
    test('commits every write across two tables together', () async {
      final db = await _open('txn_commit.db');

      await db.transaction((txn) async {
        final item = await items.on(txn).insert(const Item(title: 'a'));
        final label = await labels.on(txn).insert(const Label(name: 'work'));
        await links.on(txn).insert(Link(itemId: item.id!, labelId: label.id!));
      });

      expect(await items.on(db).count(), 1);
      expect(await links.on(db).count(), 1);
      await db.dispose();
    });

    test('rolls back every write across two tables when the callback throws', () async {
      final db = await _open('txn_rollback.db');

      await expectLater(
        db.transaction((txn) async {
          await items.on(txn).insert(const Item(title: 'a'));
          await labels.on(txn).insert(const Label(name: 'work'));
          throw StateError('stop');
        }),
        throwsStateError,
      );

      expect(await items.on(db).count(), 0);
      expect(await labels.on(db).count(), 0);
      await db.dispose();
    });

    test('a table read through the database inside a transaction joins the transaction instead of hanging', () async {
      final db = await _open('txn_join.db');

      await db
          .transaction((txn) async {
            await items.on(db).insert(const Item(title: 'a'));
            expect(await items.on(db).count(), 1);
            throw StateError('stop');
          })
          .then<void>((_) {}, onError: (Object _) {})
          .timeout(const Duration(seconds: 3));

      expect(await items.on(db).count(), 0);
      await db.dispose();
    });

    test('a transaction started inside a transaction joins it instead of hanging', () async {
      final db = await _open('txn_nested.db');

      await db
          .transaction((outer) async {
            await db.transaction((inner) async {
              await items.on(inner).insert(const Item(title: 'a'));
            });
            await items.on(outer).insert(const Item(title: 'b'));
          })
          .timeout(const Duration(seconds: 3));

      expect(await items.on(db).count(), 2);
      await db.dispose();
    });

    test('upsert inside a transaction runs in that transaction and rolls back with it', () async {
      final db = await _open('txn_upsert.db');

      await expectLater(
        db.transaction((txn) async {
          await items.on(txn).upsert(const Item(title: 'a'));
          throw StateError('stop');
        }),
        throwsStateError,
      );

      expect(await items.on(db).count(), 0);
      await db.dispose();
    });
  });

  group('Date and Time', () {
    test('order by the calendar and by the clock', () {
      expect(const Date(year: 2026, month: 1, day: 9).compareTo(const Date(year: 2026, month: 2, day: 1)), isNegative);
      expect(const Date(year: 2026, month: 2, day: 1).compareTo(const Date(year: 2026, month: 2, day: 1)), isZero);
      expect(const Time(hour: 9, minute: 30).compareTo(const Time(hour: 9, minute: 5)), isPositive);
    });
  });
}

final class _ForeignRead extends DatabaseTable<String> {
  _ForeignRead() : super('foreign_read');

  late final own = column.text('own');

  @override
  List<DatabaseField<Object?>> get columns => [own];

  @override
  String read(DatabaseReader row) => row(items.title);

  @override
  List<DatabaseAssignment> write(String record) => [own.to(record)];
}
