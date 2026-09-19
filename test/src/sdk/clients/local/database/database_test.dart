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

// A schema-validation check like test/src/sdk/clients/local/database/engine/table/typed_database_test.dart: the database
// layer is only proven against real SQLite files, through `sqflite_common_ffi`.

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
  final users = UsersTable();
  final items = ItemsTable();

  @override
  List<KeyedTable<Object, Object>> get tables => [users, items];
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
    directory = await Directory.systemTemp.createTemp('pylon_database_layer');
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
      await db.from(db.users).upsert(user);
    }
  }

  Future<List<String>> ids(Rows<User> rows) async => [for (final user in await rows.select()) user.id];

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

    test('creates the tables it lists in the app database', () async {
      expect(await LocalDatabase.instance.hasTable('users'), isTrue);
      expect(await LocalDatabase.instance.hasTable('items'), isTrue);
    });

    test('refuses a table it does not list', () async {
      expect(() => db.from(_StrayTable()), throwsStateError);
    });
  });

  group('from a keyed row', () {
    test('reads back what it upserted, typed', () async {
      await db.from(db.users).upsert(_ada);

      final user = await db.from(db.users).get('ada');

      expect((user!.id, user.name, user.age, user.city), ('ada', 'Ada', 36, 'London'));
    });

    test('reads a missing row as null', () async {
      expect(await db.from(db.users).get('nobody'), isNull);
    });

    test('replaces the whole row on upsert', () async {
      await db.from(db.users).upsert(_ada);
      await db.from(db.users).upsert(const User(id: 'ada', name: 'Ada', age: 37));

      final user = (await db.from(db.users).get('ada'))!;
      expect((user.age, user.city), (37, null));
    });

    test('updates only the columns it is given', () async {
      await db.from(db.users).upsert(_ada);

      final changed = await db.from(db.users).where(db.users.id.isEqualTo('ada')).update([
        db.users.age.to(37),
        db.users.city.to(null),
      ]);

      final user = (await db.from(db.users).get('ada'))!;
      expect(changed, 1);
      expect((user.name, user.age, user.city), ('Ada', 37, null));
    });

    test('adds to a number, and stamps a time, in one update', () async {
      await db.from(db.users).upsert(_ada);
      final before = DateTime.now().toUtc();
      final ada = db.from(db.users).where(db.users.id.isEqualTo('ada'));

      await ada.update([db.users.visits.incrementBy(2), db.users.seen.to(DateTime.now())]);
      await ada.update([db.users.visits.incrementBy(3)]);

      final user = (await db.from(db.users).get('ada'))!;
      expect(user.visits, 5);
      expect(user.seen!.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
    });

    test('an update that matches no row changes none', () async {
      final changed = await db.from(db.users).where(db.users.id.isEqualTo('nobody')).update([db.users.age.to(1)]);

      expect(changed, 0);
    });

    test('removes, and says whether there was a row to remove', () async {
      await db.from(db.users).upsert(_ada);

      expect(await db.from(db.users).remove('ada'), isTrue);
      expect(await db.from(db.users).remove('ada'), isFalse);
      expect(await db.from(db.users).get('ada'), isNull);
    });
  });

  group('insert and deleteAll', () {
    test('inserts a row under the key the engine numbers', () async {
      final first = await db.from(db.items).insert(const Item(label: 'pen', stock: 3));
      final second = await db.from(db.items).insert(const Item(label: 'ink', stock: 1));

      expect(first.id, isNot(second.id));
      expect((await db.from(db.items).get(first.id!))!.label, 'pen');
    });

    test('inserts a row under the key it carries, and never overwrites', () async {
      await db.from(db.users).insert(_ada);

      await expectLater(db.from(db.users).insert(_ada), throwsA(isA<UniqueConstraintError>()));
    });

    test('deletes every row and keeps the table', () async {
      await seed();

      await db.from(db.users).deleteAll();

      expect(await db.from(db.users).count(), 0);
      expect(await LocalDatabase.instance.hasTable('users'), isTrue);
    });
  });

  group('where, orderBy, limit and select', () {
    setUp(seed);

    test('matches everything when unconstrained', () async {
      expect((await ids(db.from(db.users))).toSet(), {'ada', 'bob', 'cyd', 'dee'});
      expect(await db.from(db.users).count(), 4);
    });

    test('filters on equality, ranges, membership and null', () async {
      final t = db.users;

      expect(await ids(db.from(t).where(t.city.isEqualTo('Paris')).orderBy((o) => o.asc(t.id))), ['bob', 'cyd']);
      expect(await ids(db.from(t).where(t.age.isNotEqualTo(17)).orderBy((o) => o.asc(t.id))), ['ada', 'cyd', 'dee']);
      expect(await ids(db.from(t).where(t.age.isLessThan(28))), ['bob']);
      expect(await ids(db.from(t).where(t.age.isGreaterThanOrEqualTo(36)).orderBy((o) => o.asc(t.id))), ['ada', 'cyd']);
      expect(await ids(db.from(t).where(t.age.isBetween(17, 28)).orderBy((o) => o.asc(t.id))), ['bob', 'dee']);
      expect(await ids(db.from(t).where(t.id.isIn(['ada', 'dee'])).orderBy((o) => o.asc(t.id))), ['ada', 'dee']);
      expect(await ids(db.from(t).where(t.city.isNull())), ['dee']);
    });

    test('combines filters with and, or and not', () async {
      final t = db.users;

      expect(await ids(db.from(t).where(t.age.isGreaterThan(20)).where(t.city.isEqualTo('Paris'))), ['cyd']);
      expect(await ids(db.from(t).where(t.age.isLessThan(18) | t.age.isGreaterThan(50)).orderBy((o) => o.asc(t.id))), [
        'bob',
        'cyd',
      ]);
      expect(await ids(db.from(t).where(~t.city.isEqualTo('Paris')).orderBy((o) => o.asc(t.id))), ['ada', 'dee']);
    });

    test('matches text without reading % or _ as a pattern', () async {
      final t = db.users;

      expect(await ids(db.from(t).where(t.name.startsWith('A'))), ['ada']);
      expect(await ids(db.from(t).where(t.name.endsWith('b'))), ['bob']);
    });

    test('orders ascending and descending, breaking ties with the next order', () async {
      final t = db.users;

      expect(await ids(db.from(t).orderBy((o) => o.asc(t.age))), ['bob', 'dee', 'ada', 'cyd']);
      expect(await ids(db.from(t).orderBy((o) => o.desc(t.age))), ['cyd', 'ada', 'dee', 'bob']);
      expect(await ids(db.from(t).orderBy((o) => o.asc(t.city).desc(t.age))).then((l) => l.sublist(1)), [
        'ada',
        'cyd',
        'bob',
      ]);
    });

    test('limits and skips', () async {
      final ordered = db.from(db.users).orderBy((o) => o.asc(db.users.age));

      expect(await ids(ordered.limit(2)), ['bob', 'dee']);
      expect(await ids(ordered.limit(2).offset(1)), ['dee', 'ada']);
      expect(await ids(ordered.offset(3)), ['cyd']);
    });

    test('answers the first row and a count', () async {
      final t = db.users;

      expect((await db.from(t).orderBy((o) => o.desc(t.age)).first())!.id, 'cyd');
      expect(await db.from(t).where(t.age.isGreaterThan(100)).first(), isNull);
      expect(await db.from(t).where(t.age.isGreaterThan(20)).count(), 3);
      expect(() => db.from(t).limit(1).count(), throwsStateError);
    });

    test('refuses a filter built from another table', () {
      expect(() => db.from(db.users).where(db.items.stock.isEqualTo(1)), throwsArgumentError);
    });

    test('a statement does not change the one it was built from', () async {
      final base = db.from(db.users).where(db.users.age.isGreaterThan(20));
      base.orderBy((o) => o.asc(db.users.age)).limit(1);

      expect((await ids(base)).toSet(), {'ada', 'cyd', 'dee'});
    });
  });

  group('stream', () {
    test('a statement emits its first result, then each change', () async {
      await db.from(db.users).upsert(_ada);
      final t = db.users;
      final emitted = <List<User>>[];
      final subscription = db
          .from(t)
          .where(t.age.isGreaterThan(20))
          .orderBy((o) => o.asc(t.age))
          .stream()
          .listen(emitted.add);
      await _waitFor(emitted, 1);

      await db.from(t).upsert(_bob);
      await db.from(t).upsert(_cyd);
      await _waitFor(emitted, 2);
      await db.from(t).where(t.id.isEqualTo('ada')).update([t.age.to(40)]);
      await _waitFor(emitted, 3);
      await db.from(t).remove('cyd');
      await _waitFor(emitted, 4);
      await subscription.cancel();

      expect(emitted.map((users) => users.map((u) => u.id).toList()), [
        ['ada'],
        ['ada', 'cyd'],
        ['ada', 'cyd'],
        ['ada'],
      ]);
      expect(emitted[2].first.age, 40);
    });

    test('a statement stays quiet when a write does not change its result', () async {
      await db.from(db.users).upsert(_ada);
      final emitted = <List<User>>[];
      final subscription = db.from(db.users).where(db.users.age.isGreaterThan(20)).stream().listen(emitted.add);
      await _waitFor(emitted, 1);

      await db.from(db.users).upsert(_bob);
      await db.from(db.users).upsert(_cyd);
      await _waitFor(emitted, 2);
      await subscription.cancel();

      expect(emitted, hasLength(2));
      expect(emitted[1].map((u) => u.id), ['ada', 'cyd']);
    });

    test('a row emits on create, change and removal', () async {
      final emitted = <User?>[];
      final subscription = db.from(db.users).streamOne('ada').listen(emitted.add);
      await _waitFor(emitted, 1);

      await db.from(db.users).upsert(_ada);
      await _waitFor(emitted, 2);
      await db.from(db.users).where(db.users.id.isEqualTo('ada')).update([db.users.age.to(37)]);
      await _waitFor(emitted, 3);
      await db.from(db.users).remove('ada');
      await _waitFor(emitted, 4);
      await subscription.cancel();

      expect(emitted.map((u) => u?.age), [null, 36, 37, null]);
    });

    test('a listener hears a batch and a transaction, once each', () async {
      final emitted = <int>[];
      final subscription = db.from(db.users).stream().listen((users) => emitted.add(users.length));
      await _waitFor(emitted, 1);

      await (db.batch()
            ..upsert(db.users, _ada)
            ..upsert(db.users, _bob))
          .commit();
      await _waitFor(emitted, 2);
      await db.runTransaction((tx) => tx.from(db.users).upsert(_cyd));
      await _waitFor(emitted, 3);
      await subscription.cancel();

      expect(emitted, [0, 2, 3]);
    });
  });

  group('tenants', () {
    test('keeps two tenants apart, under the same key', () async {
      Tenant.use('a');
      await db.from(db.users).upsert(const User(id: 'u1', name: 'A', age: 1));
      Tenant.use('b');

      expect(await db.from(db.users).get('u1'), isNull);
      await db.from(db.users).upsert(const User(id: 'u1', name: 'B', age: 2));
      Tenant.use('a');
      expect((await db.from(db.users).get('u1'))!.name, 'A');
    });

    test('never shows the previous account after leaving it', () async {
      Tenant.use('a');
      await db.from(db.users).upsert(_ada);

      Tenant.leave();

      expect(await db.from(db.users).count(), 0);
      Tenant.use('a');
      expect(await db.from(db.users).count(), 1);
    });

    test('lets a shared table ignore the tenant', () async {
      Tenant.use('a');
      await db.from(db.items).insert(const Item(label: 'pen', stock: 1));
      Tenant.use('b');

      expect(await db.from(db.items).count(), 1);
    });

    test('finishes an operation on the tenant it started on', () async {
      Tenant.use('a');
      final pending = db.from(db.users).upsert(_ada);
      Tenant.use('b');
      await pending;

      expect(await db.from(db.users).get('ada'), isNull);
      Tenant.use('a');
      expect(await db.from(db.users).get('ada'), isNotNull);
    });

    test('commits a batch on the tenant current when it commits', () async {
      Tenant.use('a');
      final batch = db.batch()..upsert(db.users, _ada);
      await batch.commit();
      Tenant.use('b');

      expect(await db.from(db.users).get('ada'), isNull);
      Tenant.use('a');
      expect(await db.from(db.users).get('ada'), isNotNull);
    });

    test('holds a transaction on the tenant it began on', () async {
      Tenant.use('a');
      await db.runTransaction((tx) async {
        await tx.from(db.users).upsert(_ada);
        Tenant.use('b');
        await tx.from(db.users).upsert(_bob);
      });

      Tenant.use('a');
      expect((await ids(db.from(db.users))).toSet(), {'ada', 'bob'});
      Tenant.use('b');
      expect(await db.from(db.users).count(), 0);
    });

    test('a watched statement is handed the new tenant\'s rows from scratch', () async {
      Tenant.use('a');
      await db.from(db.users).upsert(_ada);
      Tenant.use('b');
      await db.from(db.users).upsert(_bob);
      Tenant.use('a');
      final emitted = <List<User>>[];
      final subscription = db.from(db.users).stream().listen(emitted.add);
      await _waitFor(emitted, 1);

      Tenant.use('b');
      await _waitFor(emitted, 2);
      await subscription.cancel();

      expect(emitted[1].map((u) => u.id), ['bob']);
    });

    test('a purge of the current tenant is heard', () async {
      Tenant.use('a');
      await db.from(db.users).upsert(_ada);
      final emitted = <int>[];
      final subscription = db.from(db.users).stream().listen((users) => emitted.add(users.length));
      await _waitFor(emitted, 1);

      await db.purgeCurrentTenant();
      await _waitFor(emitted, 2);
      await subscription.cancel();

      expect(emitted, [1, 0]);
    });

    test('carries the anonymous rows over to an account', () async {
      await db.from(db.users).upsert(const User(id: 'guest', name: 'G', age: 1));
      Tenant.use('a');
      await db.from(db.users).upsert(_ada);

      final moved = await db.adoptAnonymousRows();

      expect(moved, 1);
      expect((await ids(db.from(db.users))).toSet(), {'guest', 'ada'});
      Tenant.leave();
      expect(await db.from(db.users).count(), 0);
    });
  });

  group('the whole-database mechanism', () {
    setUp(() async {
      Tenant.use('a');
      await db.from(db.users).upsert(_ada);
      Tenant.use('b');
      await db.from(db.users).upsert(_bob);
      Tenant.leave();
      await db.from(db.users).upsert(const User(id: 'guest', name: 'G', age: 1));
    });

    test('reads every tenant, and says whose each row is', () async {
      final rows = await db
          .fromWholeDatabase(db.users, SecureStorage.fingerprint)
          .orderBy((o) => o.asc(db.users.id))
          .listWithTenants();

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
      expect(() => db.fromWholeDatabase(db.users, other), throwsStateError);
    });
  });

  group('Batch', () {
    test('applies every write together', () async {
      await db.from(db.users).upsert(const User(id: 'gone', name: 'G', age: 1));
      final item = await db.from(db.items).insert(const Item(label: 'pen', stock: 5));

      await (db.batch()
            ..upsert(db.users, _ada)
            ..update(db.items, item.id!, [db.items.stock.incrementBy(-1)])
            ..remove(db.users, 'gone'))
          .commit();

      expect(await db.from(db.users).get('ada'), isNotNull);
      expect((await db.from(db.items).get(item.id!))!.stock, 4);
      expect(await db.from(db.users).get('gone'), isNull);
    });

    test('inserts a row, and refuses to overwrite one', () async {
      await (db.batch()..insert(db.users, _ada)).commit();

      expect(await db.from(db.users).get('ada'), isNotNull);
      await expectLater((db.batch()..insert(db.users, _ada)).commit(), throwsA(isA<UniqueConstraintError>()));
    });

    test('applies none of them when one fails', () async {
      final batch = db.batch()
        ..upsert(db.users, const User(id: 'ok', name: 'Ok', age: 1))
        ..update(db.users, 'missing', [db.users.age.to(2)]);

      await expectLater(batch.commit(), throwsA(isA<RowNotFoundError>()));
      expect(await db.from(db.users).get('ok'), isNull);
    });

    test('commits once', () async {
      final batch = db.batch()..upsert(db.users, const User(id: 'a', name: 'A', age: 1));
      await batch.commit();

      expect(batch.commit, throwsStateError);
      expect(() => batch.remove(db.users, 'a'), throwsStateError);
    });
  });

  group('runTransaction', () {
    test('reads what it wrote and commits together', () async {
      final item = await db.from(db.items).insert(const Item(label: 'pen', stock: 5));

      final remaining = await db.runTransaction((tx) async {
        final current = (await tx.from(db.items).get(item.id!))!;
        await tx.from(db.items).where(db.items.id.isEqualTo(item.id!)).update([db.items.stock.to(current.stock - 2)]);
        await tx.from(db.users).upsert(const User(id: 'buyer', name: 'B', age: 30));
        return (await tx.from(db.items).get(item.id!))!.stock;
      });

      expect(remaining, 3);
      expect(await db.from(db.users).get('buyer'), isNotNull);
    });

    test('rolls everything back when the action throws', () async {
      await expectLater(
        db.runTransaction((tx) async {
          await tx.from(db.users).upsert(const User(id: 'a', name: 'A', age: 1));
          throw StateError('nope');
        }),
        throwsStateError,
      );

      expect(await db.from(db.users).get('a'), isNull);
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
