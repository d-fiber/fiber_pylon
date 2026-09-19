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

// A schema-validation check like test/src/sdk/clients/local/database/engine/table/typed_database_test.dart: the collections
// are only proven against real SQLite files, through `sqflite_common_ffi`.

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

final class User {
  const User({required this.id, required this.name, required this.age, this.city, this.visits = 0, this.seen});

  final String id;
  final String name;
  final int age;
  final String? city;
  final int visits;
  final DateTime? seen;
}

/// Isolated: every tenant has users of its own.
final class UsersTable extends KeyedTable<User, String> {
  UsersTable() : super('users');

  late final id = column.text('id').primaryKey();
  late final name = column.text('name');
  late final age = column.integer('age');
  late final city = column.text('city').nullable();
  late final visits = column.integer('visits').defaultsTo(0);
  late final seen = column.timestamp('seen').nullable();

  @override
  Tunnel get tunnel => Tunnel.isolated;

  @override
  List<Field<Object?>> get columns => [id, name, age, city, visits, seen];

  @override
  User read(Reader row) =>
      User(id: row(id), name: row(name), age: row(age), city: row(city), visits: row(visits), seen: row(seen));

  @override
  List<Assignment> write(User user) => [
    id.to(user.id),
    name.to(user.name),
    age.to(user.age),
    city.to(user.city),
    visits.to(user.visits),
    seen.to(user.seen),
  ];
}

final class Item {
  const Item({this.id, required this.label, required this.stock});

  final int? id;
  final String label;
  final int stock;
}

/// Shared, with a key the engine numbers itself.
final class ItemsTable extends KeyedTable<Item, int> {
  ItemsTable() : super('items');

  late final id = column.key();
  late final label = column.text('label');
  late final stock = column.integer('stock');

  @override
  List<Field<Object?>> get columns => [id, label, stock];

  @override
  Item read(Reader row) => Item(id: row(id), label: row(label), stock: row(stock));

  @override
  List<Assignment> write(Item item) => [id.toOrGenerate(item.id), label.to(item.label), stock.to(item.stock)];
}

final class OwnDatabase extends pylon.Database {
  final usersTable = UsersTable();
  final itemsTable = ItemsTable();
  late final users = Collection(usersTable);
  late final items = Collection(itemsTable);

  @override
  List<Collection<Object, Object>> get collections => [users, items];
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

const _ada = User(id: 'ada', name: 'Ada', age: 36, city: 'London');
const _bob = User(id: 'bob', name: 'Bob', age: 17, city: 'Paris');
const _cyd = User(id: 'cyd', name: 'Cyd', age: 52, city: 'Paris');
const _dee = User(id: 'dee', name: 'Dee', age: 28);

void main() {
  late Directory directory;
  late OwnDatabase db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    Tenant.leave();
    directory = await Directory.systemTemp.createTemp('pylon_collections');
    databaseFactoryFfi.setDatabasesPath(directory.path);
    PackageInfo.setMockInitialValues(
      appName: 'Fiber',
      packageName: 'dev.fiber.app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    LocalDatabase.encryption = EncryptionPolicy.off;
    await GetIt.instance.reset();
    await configureSdk();
    db = OwnDatabase();
    await db.initialize();
  });

  tearDown(() async {
    Tenant.leave();
    await db.dispose();
    await GetIt.instance.reset();
    await directory.delete(recursive: true);
  });

  Future<void> seed() async {
    for (final user in [_ada, _bob, _cyd, _dee]) {
      await db.users.doc(user.id).set(user);
    }
  }

  Future<List<String>> ids(Query<User, String> query) async => [for (final doc in (await query.get()).docs) doc.id];

  group('Database', () {
    test('is reachable from anywhere once initialized', () {
      expect(pylon.Database.instance<OwnDatabase>(), same(db));
    });

    test('refuses to initialize before configureSdk', () async {
      await db.dispose();
      await GetIt.instance.reset();

      await expectLater(OwnDatabase().initialize(), throwsA(isA<StateError>()));
    });

    test('is not reachable once disposed', () async {
      await db.dispose();

      expect(() => pylon.Database.instance<OwnDatabase>(), throwsStateError);
    });

    test('creates the tables of its collections in the app database', () async {
      expect(await LocalDatabase.instance.hasTable('users'), isTrue);
      expect(await LocalDatabase.instance.hasTable('items'), isTrue);
    });

    test('a collection it does not list has no table', () async {
      final stray = Collection(_StrayTable());

      await expectLater(stray.get(), throwsStateError);
    });
  });

  group('DocumentReference', () {
    test('reads back what it set, typed', () async {
      await db.users.doc('ada').set(_ada);

      final snapshot = await db.users.doc('ada').get();

      expect(snapshot.exists, isTrue);
      final user = snapshot.data()!;
      expect((user.id, user.name, user.age, user.city), ('ada', 'Ada', 36, 'London'));
    });

    test('reads a missing document as one that does not exist', () async {
      final snapshot = await db.users.doc('nobody').get();

      expect(snapshot.exists, isFalse);
      expect(snapshot.data(), isNull);
      expect(snapshot.id, 'nobody');
    });

    test('replaces the whole document on set', () async {
      await db.users.doc('ada').set(_ada);
      await db.users.doc('ada').set(const User(id: 'ada', name: 'Ada', age: 37));

      final user = (await db.users.doc('ada').get()).data()!;
      expect((user.age, user.city), (37, null));
    });

    test('refuses a record that carries another key than the document\'s', () async {
      await expectLater(() => db.users.doc('zed').set(_ada), throwsArgumentError);
    });

    test('updates only the columns it is given', () async {
      await db.users.doc('ada').set(_ada);

      await db.users.doc('ada').update([db.usersTable.age.to(37), db.usersTable.city.to(null)]);

      final user = (await db.users.doc('ada').get()).data()!;
      expect((user.name, user.age, user.city), ('Ada', 37, null));
    });

    test('adds to a number, and stamps a time, in one update', () async {
      await db.users.doc('ada').set(_ada);
      final before = DateTime.now().toUtc();

      await db.users.doc('ada').update([db.usersTable.visits.incrementBy(2), db.usersTable.seen.to(DateTime.now())]);
      await db.users.doc('ada').update([db.usersTable.visits.incrementBy(3)]);

      final user = (await db.users.doc('ada').get()).data()!;
      expect(user.visits, 5);
      expect(user.seen!.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
    });

    test('fails to update a document that does not exist', () async {
      await expectLater(
        db.users.doc('nobody').update([db.usersTable.age.to(1)]),
        throwsA(isA<DocumentNotFoundError>()),
      );
    });

    test('deletes, and deleting what is not there is fine', () async {
      await db.users.doc('ada').set(_ada);

      await db.users.doc('ada').delete();
      await db.users.doc('ada').delete();

      expect((await db.users.doc('ada').get()).exists, isFalse);
    });

    test('compares two references by collection and key', () {
      expect(db.users.doc('a'), db.users.doc('a'));
      expect(db.users.doc('a'), isNot(db.users.doc('b')));
    });
  });

  group('Collection', () {
    test('adds a document under the key the engine numbers', () async {
      final first = await db.items.add(const Item(label: 'pen', stock: 3));
      final second = await db.items.add(const Item(label: 'ink', stock: 1));

      expect(first.id, isNot(second.id));
      expect((await first.get()).data()!.label, 'pen');
    });

    test('adds a document under the key it carries, and never overwrites', () async {
      await db.users.add(_ada);

      await expectLater(db.users.add(_ada), throwsA(isA<UniqueConstraintError>()));
    });

    test('clears its documents and keeps the table', () async {
      await seed();

      await db.users.clear();

      expect(await db.users.count(), 0);
      expect(await LocalDatabase.instance.hasTable('users'), isTrue);
    });
  });

  group('Query', () {
    setUp(seed);

    test('matches everything when unconstrained', () async {
      expect((await ids(db.users)).toSet(), {'ada', 'bob', 'cyd', 'dee'});
      expect(await db.users.count(), 4);
    });

    test('filters on equality, ranges, membership and null', () async {
      final t = db.usersTable;

      expect(await ids(db.users.where(t.city.isEqualTo('Paris')).orderBy([t.id.asc()])), ['bob', 'cyd']);
      expect(await ids(db.users.where(t.age.isNotEqualTo(17)).orderBy([t.id.asc()])), ['ada', 'cyd', 'dee']);
      expect(await ids(db.users.where(t.age.isLessThan(28))), ['bob']);
      expect(await ids(db.users.where(t.age.isGreaterThanOrEqualTo(36)).orderBy([t.id.asc()])), ['ada', 'cyd']);
      expect(await ids(db.users.where(t.age.isBetween(17, 28)).orderBy([t.id.asc()])), ['bob', 'dee']);
      expect(await ids(db.users.where(t.id.isIn(['ada', 'dee'])).orderBy([t.id.asc()])), ['ada', 'dee']);
      expect(await ids(db.users.where(t.city.isNull())), ['dee']);
    });

    test('combines filters with and, or and not', () async {
      final t = db.usersTable;

      expect(await ids(db.users.where(t.age.isGreaterThan(20)).where(t.city.isEqualTo('Paris'))), ['cyd']);
      expect(await ids(db.users.where(t.age.isLessThan(18) | t.age.isGreaterThan(50)).orderBy([t.id.asc()])), [
        'bob',
        'cyd',
      ]);
      // A NOT keeps what the filter cannot decide on too: Dee has no city.
      expect(await ids(db.users.where(~t.city.isEqualTo('Paris')).orderBy([t.id.asc()])), ['ada', 'dee']);
    });

    test('matches text without reading % or _ as a pattern', () async {
      final t = db.usersTable;

      expect(await ids(db.users.where(t.name.startsWith('A'))), ['ada']);
      expect(await ids(db.users.where(t.name.endsWith('b'))), ['bob']);
    });

    test('orders ascending and descending, breaking ties with the next order', () async {
      final t = db.usersTable;

      expect(await ids(db.users.orderBy([t.age.asc()])), ['bob', 'dee', 'ada', 'cyd']);
      expect(await ids(db.users.orderBy([t.age.desc()])), ['cyd', 'ada', 'dee', 'bob']);
      expect(await ids(db.users.orderBy([t.city.asc(), t.age.desc()])).then((l) => l.sublist(1)), [
        'ada',
        'cyd',
        'bob',
      ]);
    });

    test('limits and skips', () async {
      final ordered = db.users.orderBy([db.usersTable.age.asc()]);

      expect(await ids(ordered.limit(2)), ['bob', 'dee']);
      expect(await ids(ordered.limit(2).offset(1)), ['dee', 'ada']);
      expect(await ids(ordered.offset(3)), ['cyd']);
    });

    test('answers the first document and a count', () async {
      final t = db.usersTable;

      expect((await db.users.orderBy([t.age.desc()]).first())!.id, 'cyd');
      expect(await db.users.where(t.age.isGreaterThan(100)).first(), isNull);
      expect(await db.users.where(t.age.isGreaterThan(20)).count(), 3);
      expect(() => db.users.limit(1).count(), throwsStateError);
    });

    test('refuses a filter built from another table', () {
      expect(() => db.users.where(db.itemsTable.stock.isEqualTo(1)), returnsNormally);
      expect(() => db.users.where(db.itemsTable.stock.isEqualTo(1)).get(), throwsArgumentError);
    });

    test('a query does not change the one it was built from', () async {
      final base = db.users.where(db.usersTable.age.isGreaterThan(20));
      base.orderBy([db.usersTable.age.asc()]).limit(1);

      expect((await ids(base)).toSet(), {'ada', 'cyd', 'dee'});
    });
  });

  group('snapshots', () {
    test('a query emits its first result, then each change', () async {
      await db.users.doc('ada').set(_ada);
      final t = db.usersTable;
      final emitted = <QuerySnapshot<User, String>>[];
      final subscription = db.users
          .where(t.age.isGreaterThan(20))
          .orderBy([t.age.asc()])
          .snapshots()
          .listen(emitted.add);
      await _waitFor(emitted, 1);

      await db.users.doc('bob').set(_bob);
      await db.users.doc('cyd').set(_cyd);
      await _waitFor(emitted, 2);
      await db.users.doc('ada').update([t.age.to(40)]);
      await _waitFor(emitted, 3);
      await db.users.doc('cyd').delete();
      await _waitFor(emitted, 4);
      await subscription.cancel();

      expect(emitted.map((s) => s.items.map((u) => u.id).toList()), [
        ['ada'],
        ['ada', 'cyd'],
        ['ada', 'cyd'],
        ['ada'],
      ]);
      expect(emitted[0].docChanges.single.type, DocumentChangeType.added);
      expect(emitted[1].docChanges.single.type, DocumentChangeType.added);
      expect(emitted[2].docChanges.single.type, DocumentChangeType.modified);
      expect(emitted[3].docChanges.single.type, DocumentChangeType.removed);
      expect(emitted[3].docChanges.single.oldIndex, 1);
      expect(emitted[3].docChanges.single.newIndex, -1);
    });

    test('a query stays quiet when a write does not change its result', () async {
      await db.users.doc('ada').set(_ada);
      final emitted = <QuerySnapshot<User, String>>[];
      final subscription = db.users.where(db.usersTable.age.isGreaterThan(20)).snapshots().listen(emitted.add);
      await _waitFor(emitted, 1);

      await db.users.doc('bob').set(_bob);
      await db.users.doc('cyd').set(_cyd);
      await _waitFor(emitted, 2);
      await subscription.cancel();

      expect(emitted, hasLength(2));
      expect(emitted[1].docChanges.map((c) => c.doc.id), ['cyd']);
    });

    test('a moved document is a modification, a shifted one is not', () async {
      await seed();
      final t = db.usersTable;
      final emitted = <QuerySnapshot<User, String>>[];
      final subscription = db.users.orderBy([t.age.asc()]).snapshots().listen(emitted.add);
      await _waitFor(emitted, 1);

      await db.users.doc('bob').delete();
      await _waitFor(emitted, 2);
      await db.users.doc('dee').update([t.age.to(60)]);
      await _waitFor(emitted, 3);
      await subscription.cancel();

      expect(emitted[1].docChanges.map((c) => (c.type, c.doc.id)), [(DocumentChangeType.removed, 'bob')]);
      expect(emitted[2].docChanges.map((c) => (c.type, c.doc.id)), [(DocumentChangeType.modified, 'dee')]);
    });

    test('a document emits on create, change and delete', () async {
      final emitted = <User?>[];
      final subscription = db.users.doc('ada').snapshots().listen((s) => emitted.add(s.data()));
      await _waitFor(emitted, 1);

      await db.users.doc('ada').set(_ada);
      await _waitFor(emitted, 2);
      await db.users.doc('ada').update([db.usersTable.age.to(37)]);
      await _waitFor(emitted, 3);
      await db.users.doc('ada').delete();
      await _waitFor(emitted, 4);
      await subscription.cancel();

      expect(emitted.map((u) => u?.age), [null, 36, 37, null]);
    });

    test('a listener hears a batch and a transaction, once each', () async {
      final emitted = <int>[];
      final subscription = db.users.snapshots().listen((s) => emitted.add(s.size));
      await _waitFor(emitted, 1);

      await (db.batch()
            ..set(db.users.doc('ada'), _ada)
            ..set(db.users.doc('bob'), _bob))
          .commit();
      await _waitFor(emitted, 2);
      await db.runTransaction((tx) => tx.set(db.users.doc('cyd'), _cyd));
      await _waitFor(emitted, 3);
      await subscription.cancel();

      expect(emitted, [0, 2, 3]);
    });
  });

  group('tenants', () {
    test('keeps two tenants apart, under the same key', () async {
      Tenant.use('a');
      await db.users.doc('u1').set(const User(id: 'u1', name: 'A', age: 1));
      Tenant.use('b');

      expect((await db.users.doc('u1').get()).exists, isFalse);
      await db.users.doc('u1').set(const User(id: 'u1', name: 'B', age: 2));
      Tenant.use('a');
      expect((await db.users.doc('u1').get()).data()!.name, 'A');
    });

    test('never shows the previous account after leaving it', () async {
      Tenant.use('a');
      await db.users.doc('ada').set(_ada);

      Tenant.leave();

      expect(await db.users.count(), 0);
      Tenant.use('a');
      expect(await db.users.count(), 1);
    });

    test('lets a shared collection ignore the tenant', () async {
      Tenant.use('a');
      await db.items.add(const Item(label: 'pen', stock: 1));
      Tenant.use('b');

      expect(await db.items.count(), 1);
    });

    test('finishes an operation on the tenant it started on', () async {
      Tenant.use('a');
      final pending = db.users.doc('ada').set(_ada);
      Tenant.use('b');
      await pending;

      expect((await db.users.doc('ada').get()).exists, isFalse);
      Tenant.use('a');
      expect((await db.users.doc('ada').get()).exists, isTrue);
    });

    test('commits a batch on the tenant current when it commits', () async {
      Tenant.use('a');
      final batch = db.batch()..set(db.users.doc('ada'), _ada);
      await batch.commit();
      Tenant.use('b');

      expect((await db.users.doc('ada').get()).exists, isFalse);
      Tenant.use('a');
      expect((await db.users.doc('ada').get()).exists, isTrue);
    });

    test('holds a transaction on the tenant it began on', () async {
      Tenant.use('a');
      await db.runTransaction((tx) async {
        await tx.set(db.users.doc('ada'), _ada);
        Tenant.use('b');
        await tx.set(db.users.doc('bob'), _bob);
      });

      Tenant.use('a');
      expect((await ids(db.users)).toSet(), {'ada', 'bob'});
      Tenant.use('b');
      expect(await db.users.count(), 0);
    });

    test('a query is handed the new tenant\'s documents from scratch', () async {
      Tenant.use('a');
      await db.users.doc('ada').set(_ada);
      Tenant.use('b');
      await db.users.doc('bob').set(_bob);
      Tenant.use('a');
      final emitted = <QuerySnapshot<User, String>>[];
      final subscription = db.users.snapshots().listen(emitted.add);
      await _waitFor(emitted, 1);

      Tenant.use('b');
      await _waitFor(emitted, 2);
      await subscription.cancel();

      expect(emitted[1].items.map((u) => u.id), ['bob']);
      expect(emitted[1].docChanges.map((c) => (c.type, c.doc.id)), [(DocumentChangeType.added, 'bob')]);
    });

    test('a purge of the current tenant is heard', () async {
      Tenant.use('a');
      await db.users.doc('ada').set(_ada);
      final emitted = <int>[];
      final subscription = db.users.snapshots().listen((s) => emitted.add(s.size));
      await _waitFor(emitted, 1);

      await db.purgeCurrentTenant();
      await _waitFor(emitted, 2);
      await subscription.cancel();

      expect(emitted, [1, 0]);
    });

    test('carries the anonymous documents over to an account', () async {
      await db.users.doc('guest').set(const User(id: 'guest', name: 'G', age: 1));
      Tenant.use('a');
      await db.users.doc('ada').set(_ada);

      final moved = await db.adoptAnonymousRows();

      expect(moved, 1);
      expect((await ids(db.users)).toSet(), {'guest', 'ada'});
      Tenant.leave();
      expect(await db.users.count(), 0);
    });
  });

  group('the whole-database mechanism', () {
    setUp(() async {
      Tenant.use('a');
      await db.users.doc('ada').set(_ada);
      Tenant.use('b');
      await db.users.doc('bob').set(_bob);
      Tenant.leave();
      await db.users.doc('guest').set(const User(id: 'guest', name: 'G', age: 1));
    });

    test('reads every tenant, and says whose each document is', () async {
      final rows = await db.users.onWholeDatabase(SecureStorage.fingerprint).orderBy([
        db.usersTable.id.asc(),
      ]).listWithTenants();

      expect(rows.map((r) => (r.tenant, r.record.id)), [('a', 'ada'), ('b', 'bob'), (null, 'guest')]);
    });

    test('lists the tenants and moves rows between them', () async {
      final whole = db.wholeDatabase(SecureStorage.fingerprint);

      expect(await whole.tenants(), ['a', 'b']);
      expect(await whole.transfer(from: 'a', to: 'c'), 1);
      expect(await whole.tenants(), ['b', 'c']);
    });

    test('is closed to any other fingerprint', () {
      final other = Fingerprint.generate();

      expect(() => db.wholeDatabase(other), throwsStateError);
      expect(() => db.users.onWholeDatabase(other), throwsStateError);
    });
  });

  group('WriteBatch', () {
    test('applies every write together', () async {
      await db.users.doc('gone').set(const User(id: 'gone', name: 'G', age: 1));
      final item = await db.items.add(const Item(label: 'pen', stock: 5));

      await (db.batch()
            ..set(db.users.doc('ada'), _ada)
            ..update(item, [db.itemsTable.stock.incrementBy(-1)])
            ..delete(db.users.doc('gone')))
          .commit();

      expect((await db.users.doc('ada').get()).exists, isTrue);
      expect((await item.get()).data()!.stock, 4);
      expect((await db.users.doc('gone').get()).exists, isFalse);
    });

    test('applies none of them when one fails', () async {
      final batch = db.batch()
        ..set(db.users.doc('ok'), const User(id: 'ok', name: 'Ok', age: 1))
        ..update(db.users.doc('missing'), [db.usersTable.age.to(2)]);

      await expectLater(batch.commit(), throwsA(isA<DocumentNotFoundError>()));
      expect((await db.users.doc('ok').get()).exists, isFalse);
    });

    test('commits once', () async {
      final batch = db.batch()..set(db.users.doc('a'), const User(id: 'a', name: 'A', age: 1));
      await batch.commit();

      expect(batch.commit, throwsStateError);
      expect(() => batch.delete(db.users.doc('a')), throwsStateError);
    });
  });

  group('runTransaction', () {
    test('reads what it wrote and commits together', () async {
      final item = await db.items.add(const Item(label: 'pen', stock: 5));

      final remaining = await db.runTransaction((tx) async {
        final current = (await tx.get(item)).data()!;
        await tx.update(item, [db.itemsTable.stock.to(current.stock - 2)]);
        await tx.set(db.users.doc('buyer'), const User(id: 'buyer', name: 'B', age: 30));
        return (await tx.get(item)).data()!.stock;
      });

      expect(remaining, 3);
      expect((await db.users.doc('buyer').get()).exists, isTrue);
    });

    test('rolls everything back when the action throws', () async {
      await expectLater(
        db.runTransaction((tx) async {
          await tx.set(db.users.doc('a'), const User(id: 'a', name: 'A', age: 1));
          throw StateError('nope');
        }),
        throwsStateError,
      );

      expect((await db.users.doc('a').get()).exists, isFalse);
    });
  });
}

final class _StrayTable extends KeyedTable<Item, int> {
  _StrayTable() : super('stray');

  late final id = column.key();
  late final label = column.text('label');

  @override
  List<Field<Object?>> get columns => [id, label];

  @override
  Item read(Reader row) => Item(id: row(id), label: row(label), stock: 0);

  @override
  List<Assignment> write(Item item) => [id.toOrGenerate(item.id), label.to(item.label)];
}
