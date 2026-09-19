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

// A schema-validation check like test/local_database_test.dart: it runs the
// typed document API against real SQLite files through `sqflite_common_ffi`,
// since the SQL it compiles is only proven by a real engine running it.

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

final class User implements Model {
  const User({this.id = '', required this.name, required this.age, this.tags = const [], this.city});

  static const name_ = Field<String>('name');
  static const age_ = Field<int>('age');
  static const city_ = Field<String>('address.city');
  static const tags_ = ListField<String>('tags');
  static const seen_ = Field<DateTime>('seen');
  static const note_ = Field<String>('note');

  @override
  final String id;
  final String name;
  final int age;
  final List<String> tags;
  final String? city;

  factory User.fromJson(String id, Map<String, Object?> json) => User(
    id: id,
    name: json['name']! as String,
    age: json['age']! as int,
    tags: (json['tags'] as List? ?? const []).cast<String>(),
    city: (json['address'] as Map?)?['city'] as String?,
  );

  @override
  Map<String, Object?> toJson() => {
    'name': name,
    'age': age,
    'tags': tags,
    if (city != null) 'address': {'city': city},
  };
}

final class Item implements Model {
  static const label_ = Field<String>('label');
  static const stock_ = Field<int>('stock');
  static const addedAt_ = Field<DateTime>('addedAt');
  static const price_ = Field<int>('price');

  const Item({this.id = '', required this.label, required this.stock, required this.addedAt});

  @override
  final String id;
  final String label;
  final int stock;
  final DateTime addedAt;

  factory Item.fromJson(String id, Map<String, Object?> json) => Item(
    id: id,
    label: json['label']! as String,
    stock: json['stock']! as int,
    addedAt: DateTime.parse(json['addedAt']! as String),
  );

  @override
  Map<String, Object?> toJson() => {'label': label, 'stock': stock, 'addedAt': addedAt};
}

/// A model whose own JSON asks the store to compute values: what a
/// `FieldValue` inside `toJson` is for.
final class Visit implements Model {
  static const note_ = Field<String>('note');
  static const nestedCount_ = Field<int>('nested.count');

  const Visit({this.id = '', this.hits = 0, this.seen});

  @override
  final String id;
  final int hits;
  final String? seen;

  factory Visit.fromJson(String id, Map<String, Object?> json) =>
      Visit(id: id, hits: json['hits']! as int, seen: json['seen'] as String?);

  @override
  Map<String, Object?> toJson() => {
    'hits': const FieldValue.increment(1),
    'seen': const FieldValue.serverTimestamp(),
    'note': const FieldValue.delete(),
    'nested': {'count': const FieldValue.increment(2)},
  };
}

/// A model whose JSON holds something JSON cannot carry.
final class _Bad implements Model {
  const _Bad();

  @override
  String get id => '';

  @override
  Map<String, Object?> toJson() => {'x': Object()};
}

final class OwnDatabase extends pylon.Database {
  final users = Collection<User>('users', User.fromJson, indexes: [User.age_, User.city_]);
  final items = Collection<Item>('items', Item.fromJson);
  final visits = Collection<Visit>('visits', Visit.fromJson);
  final catalogue = Collection<Item>('catalogue', Item.fromJson, tunnel: Tunnel.shared);
}

Future<void> _seed(OwnDatabase db) async {
  await db.users.doc('ada').set(const User(name: 'Ada', age: 36, tags: ['math', 'code'], city: 'London'));
  await db.users.doc('bob').set(const User(name: 'Bob', age: 17, tags: ['code'], city: 'Paris'));
  await db.users.doc('cyd').set(const User(name: 'Cyd', age: 52, tags: ['art'], city: 'Paris'));
  await db.users.doc('dee').set(const User(name: 'Dee', age: 28));
}

/// Waits until [list] holds [count] items: a stream's next emission needs a
/// real database round trip, which no fixed number of event-loop turns covers.
Future<void> _waitFor(List<Object?> list, int count) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (list.length < count) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Waited for $count item(s), got ${list.length}.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<List<String>> _ids(Query<User> query) async => [for (final doc in (await query.get()).docs) doc.id];

void main() {
  late Directory directory;
  late OwnDatabase db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    Tenant.leave();
    directory = await Directory.systemTemp.createTemp('pylon_document_database');
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
    AppStorage.encryption = EncryptionPolicy.off;
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
  });

  group('Collection', () {
    test('creates its table, and its indexes, in the app database', () async {
      await db.users.doc('ada').get();

      expect(await AppStorage.tableExists('users'), isTrue);
      final indexes = await AppStorage.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'users'",
      );
      expect(indexes.map((row) => row['name']!.asString), containsAll(['users_age_idx', 'users_address_city_idx']));
    });

    test('rejects a name that is not a table name', () {
      expect(() => Collection<User>('bad name', User.fromJson), throwsArgumentError);
      expect(() => Collection<User>('sqlite_x', User.fromJson), throwsArgumentError);
      expect(() => Collection<User>('1st', User.fromJson), throwsArgumentError);
    });

    test('refuses to take over a table that is not its own', () async {
      await AppStorage.execute('CREATE TABLE foreign_table (a TEXT, b TEXT)');
      final foreign = Collection<User>('foreign_table', User.fromJson);

      await expectLater(foreign.doc('x').get(), throwsA(isA<StateError>()));
    });

    test('adopts a table it already created on an earlier launch', () async {
      await db.users.doc('ada').set(const User(name: 'Ada', age: 36));

      final again = OwnDatabase();
      final snapshot = await again.users.doc('ada').get();

      expect(snapshot.data()?.name, 'Ada');
    });

    test('rejects an id that would break out of the collection', () {
      for (final id in ['', '.', '..', 'a/b']) {
        expect(() => db.users.doc(id), throwsArgumentError);
      }
    });

    test('makes 20-character ids that do not repeat', () {
      final ids = {for (var i = 0; i < 100; i++) db.users.newId()};

      expect(ids, hasLength(100));
      expect(ids.every((id) => id.length == 20), isTrue);
    });
  });

  group('DocumentReference', () {
    test('reads back what it set, typed', () async {
      await db.users.doc('ada').set(const User(name: 'Ada', age: 36, tags: ['math'], city: 'London'));

      final snapshot = await db.users.doc('ada').get();

      expect(snapshot.exists, isTrue);
      final user = snapshot.data()!;
      expect((user.id, user.name, user.age, user.city), ('ada', 'Ada', 36, 'London'));
      expect(user.tags, ['math']);
    });

    test('reads a missing document as one that does not exist', () async {
      final snapshot = await db.users.doc('nobody').get();

      expect(snapshot.exists, isFalse);
      expect(snapshot.data(), isNull);
      expect(snapshot.get(User.name_), isNull);
    });

    test('replaces the whole document on set', () async {
      await db.users.doc('ada').set(const User(name: 'Ada', age: 36, city: 'London'));
      await db.users.doc('ada').set(const User(name: 'Ada', age: 37));

      final user = (await db.users.doc('ada').get()).data()!;
      expect((user.age, user.city), (37, null));
    });

    test('merges into the document on set with merge', () async {
      await db.users.doc('ada').set(const User(name: 'Ada', age: 36, city: 'London'));
      await db.users.doc('ada').set(const User(name: 'Ada', age: 37), merge: true);

      final user = (await db.users.doc('ada').get()).data()!;
      expect((user.age, user.city), (37, 'London'));
    });

    test('keeps createTime and moves updateTime on a rewrite', () async {
      await db.users.doc('ada').set(const User(name: 'Ada', age: 36));
      final first = await db.users.doc('ada').get();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await db.users.doc('ada').set(const User(name: 'Ada', age: 37));
      final second = await db.users.doc('ada').get();

      expect(second.createTime, first.createTime);
      expect(second.updateTime!.isAfter(first.updateTime!), isTrue);
    });

    test('updates only the fields it is given, nested ones included', () async {
      await db.users.doc('ada').set(const User(name: 'Ada', age: 36, city: 'London'));

      await db.users.doc('ada').update((u) => [u(User.age_).set(37), u(User.city_).set('Paris')]);

      final user = (await db.users.doc('ada').get()).data()!;
      expect((user.name, user.age, user.city), ('Ada', 37, 'Paris'));
    });

    test('changes fields through the typed update builder', () async {
      await db.users.doc('ada').set(const User(name: 'Ada', age: 36, tags: ['math', 'code'], city: 'London'));

      await db.users
          .doc('ada')
          .update(
            (u) => [
              u(User.age_).increment(2),
              u.list(User.tags_).arrayUnion(['code', 'art']),
              u(User.city_).delete(),
              u(User.seen_).serverTimestamp(),
            ],
          );
      await db.users
          .doc('ada')
          .update(
            (u) => [
              u.list(User.tags_).arrayRemove(['math']),
            ],
          );

      final snapshot = await db.users.doc('ada').get();
      final user = snapshot.data()!;
      expect((user.age, user.city), (38, null));
      expect(user.tags, ['code', 'art']);
      expect(snapshot.get(User.seen_), isA<DateTime>());
    });

    test('applies several changes to one field in the order given', () async {
      await db.users.doc('ada').set(const User(name: 'Ada', age: 1));

      await db.users.doc('ada').update((u) => [u(User.age_).set(10), u(User.age_).increment(5)]);

      expect((await db.users.doc('ada').get()).data()!.age, 15);
    });

    test('replaces a whole list, and refuses an update that changes nothing', () async {
      await db.users.doc('ada').set(const User(name: 'Ada', age: 1, tags: ['a']));

      await db.users
          .doc('ada')
          .update(
            (u) => [
              u.list(User.tags_).set(['x', 'y']),
            ],
          );

      expect((await db.users.doc('ada').get()).data()!.tags, ['x', 'y']);
      expect(() => db.users.doc('ada').update((u) => []), throwsArgumentError);
    });

    test('fails to update a document that does not exist', () async {
      await expectLater(
        db.users.doc('nobody').update((u) => [u(User.age_).set(1)]),
        throwsA(isA<DocumentNotFoundError>()),
      );
    });

    test('deletes, and deleting what is not there is fine', () async {
      await db.users.doc('ada').set(const User(name: 'Ada', age: 36));

      await db.users.doc('ada').delete();
      await db.users.doc('ada').delete();

      expect((await db.users.doc('ada').get()).exists, isFalse);
    });

    test('reads a field back as the type it is declared to hold', () async {
      await db.users.doc('ada').set(const User(name: 'Ada', age: 36, tags: ['math'], city: 'London'));

      final snapshot = await db.users.doc('ada').get();

      expect(snapshot.get(User.city_), 'London');
      expect(snapshot.get(User.age_), 36);
      expect(snapshot.getList(User.tags_), ['math']);
      expect(snapshot.get(Field.documentId), 'ada');
      expect(snapshot.get(User.note_), isNull);
    });

    test('reads a whole number as a double, and refuses a field that disagrees with its declaration', () async {
      await db.users.doc('ada').set(const User(name: 'Ada', age: 36));
      final snapshot = await db.users.doc('ada').get();

      expect(snapshot.get(const Field<double>('age')), 36.0);
      expect(() => snapshot.get(const Field<String>('age')), throwsStateError);
      expect(() => snapshot.getList(const ListField<int>('name')), throwsStateError);
    });

    test('stores a DateTime and an unsupported value is refused', () async {
      await db.items.doc('i1').set(Item(label: 'pen', stock: 3, addedAt: DateTime.utc(2026, 1, 2, 3, 4, 5)));

      expect((await db.items.doc('i1').get()).data()!.addedAt, DateTime.utc(2026, 1, 2, 3, 4, 5));
      await expectLater(
        Collection<_Bad>('bad', (id, json) => const _Bad()).doc('x').set(const _Bad()),
        throwsArgumentError,
      );
    });

    test('compares two references by collection and id', () {
      expect(db.users.doc('a'), db.users.doc('a'));
      expect(db.users.doc('a'), isNot(db.users.doc('b')));
    });
  });

  group('Collection.add', () {
    test('assigns an id when the model has none', () async {
      final reference = await db.users.add(const User(name: 'Eve', age: 30));

      expect(reference.id, hasLength(20));
      expect((await reference.get()).data()!.id, reference.id);
    });

    test('keeps the id the model carries, and never overwrites', () async {
      await db.users.add(const User(id: 'eve', name: 'Eve', age: 30));

      expect((await db.users.doc('eve').get()).data()!.name, 'Eve');
      await expectLater(db.users.add(const User(id: 'eve', name: 'Other', age: 1)), throwsA(isA<DatabaseError>()));
    });
  });

  group('Query', () {
    setUp(() => _seed(db));

    test('matches everything, in id order, when unconstrained', () async {
      expect(await _ids(db.users), ['ada', 'bob', 'cyd', 'dee']);
    });

    test('filters on equality, inequality and ranges', () async {
      expect(await _ids(db.users.where((w) => w(const Field<String>('city')).isEqualTo('x'))), isEmpty);
      expect(await _ids(db.users.where((w) => w(User.city_).isEqualTo('Paris'))), ['bob', 'cyd']);
      expect(await _ids(db.users.where((w) => w(User.age_).isNotEqualTo(17))), ['ada', 'cyd', 'dee']);
      expect(await _ids(db.users.where((w) => w(User.age_).isLessThan(28))), ['bob']);
      expect(await _ids(db.users.where((w) => w(User.age_).isLessThanOrEqualTo(28))), ['bob', 'dee']);
      expect(await _ids(db.users.where((w) => w(User.age_).isGreaterThan(36))), ['cyd']);
      expect(await _ids(db.users.where((w) => w(User.age_).isGreaterThanOrEqualTo(36))), ['ada', 'cyd']);
    });

    test('combines several where calls with AND', () async {
      final query = db.users
          .where((w) => w(User.age_).isGreaterThan(20))
          .where((w) => w(User.city_).isEqualTo('Paris'));

      expect(await _ids(query), ['cyd']);
    });

    test('filters on null and on absence', () async {
      expect(await _ids(db.users.where((w) => w(User.city_).isNull())), ['dee']);
      expect(await _ids(db.users.where((w) => w(User.city_).isNotNull())), ['ada', 'bob', 'cyd']);
    });

    test('filters on membership', () async {
      expect(await _ids(db.users.where((w) => w(User.age_).isIn([17, 28]))), ['bob', 'dee']);
      expect(await _ids(db.users.where((w) => w(User.age_).isNotIn([17, 28]))), ['ada', 'cyd']);
    });

    test('filters on the contents of a list', () async {
      expect(await _ids(db.users.where((w) => w.list(User.tags_).arrayContains('code'))), ['ada', 'bob']);
      expect(await _ids(db.users.where((w) => w.list(User.tags_).arrayContainsAny(['art', 'math']))), ['ada', 'cyd']);
    });

    test('filters on the document id', () async {
      expect(await _ids(db.users.where((w) => w(Field.documentId).isIn(['ada', 'dee']))), ['ada', 'dee']);
    });

    test('combines filters with and / or / not', () async {
      final query = db.users.where(
        (w) => w.or([
          w(User.age_).isLessThan(18),
          w.and([w(User.age_).isGreaterThan(30), w(User.city_).isEqualTo('Paris')]),
        ]),
      );

      expect(await _ids(query), ['bob', 'cyd']);
      expect(await _ids(db.users.where((w) => w.not(w(User.age_).isLessThan(30)))), ['ada', 'cyd']);
    });

    test('matches text without reading % or _ as a pattern', () async {
      await db.users.doc('pct').set(const User(name: '100% Real_Name', age: 1));

      expect(await _ids(db.users.where((w) => w(User.name_).startsWith('A'))), ['ada']);
      expect(await _ids(db.users.where((w) => w(User.name_).endsWith('b'))), ['bob']);
      expect(await _ids(db.users.where((w) => w(User.name_).contains('d'))), ['ada', 'cyd', 'dee']); // case-insensitive
      expect(await _ids(db.users.where((w) => w(User.name_).contains('%'))), ['pct']);
      expect(await _ids(db.users.where((w) => w(User.name_).contains('l_N'))), ['pct']);
      expect(await _ids(db.users.where((w) => w(User.name_).contains('_'))), ['pct']);
      expect(await _ids(db.users.where((w) => w(User.name_).contains('x_y'))), isEmpty);
    });

    test('compares a DateTime, a bool and an enum against what was stored', () async {
      await db.items.doc('a').set(Item(label: 'a', stock: 1, addedAt: DateTime.utc(2026, 1, 1)));
      await db.items.doc('b').set(Item(label: 'b', stock: 2, addedAt: DateTime.utc(2026, 6, 1)));

      final later = await db.items.where((w) => w(Item.addedAt_).isGreaterThan(DateTime.utc(2026, 3, 1))).get();

      expect(later.items.map((item) => item.label), ['b']);
    });

    test('orders ascending and descending, ties by id', () async {
      expect(await _ids(db.users.orderBy((o) => [o.asc(User.age_)])), ['bob', 'dee', 'ada', 'cyd']);
      expect(await _ids(db.users.orderBy((o) => [o.desc(User.age_)])), ['cyd', 'ada', 'dee', 'bob']);
      expect(await _ids(db.users.orderBy((o) => [o.asc(User.city_)]).orderBy((o) => [o.desc(User.age_)])), [
        'ada',
        'cyd',
        'bob',
      ]);
    });

    test('leaves out a document that lacks the field it is ordered by', () async {
      expect(await _ids(db.users.orderBy((o) => [o.asc(User.city_)])), ['ada', 'bob', 'cyd']);
    });

    test('limits from the start and from the end', () async {
      expect(await _ids(db.users.orderBy((o) => [o.asc(User.age_)]).limit(2)), ['bob', 'dee']);
      expect(await _ids(db.users.orderBy((o) => [o.asc(User.age_)]).limitToLast(2)), ['ada', 'cyd']);
    });

    test('refuses limitToLast without an orderBy', () async {
      await expectLater(db.users.limitToLast(1).get(), throwsA(isA<StateError>()));
    });

    test('pages with cursors', () async {
      final ordered = db.users.orderBy((o) => [o.asc(User.age_)]);

      expect(await _ids(ordered.startAt((c) => [c(User.age_).at(28)])), ['dee', 'ada', 'cyd']);
      expect(await _ids(ordered.startAfter((c) => [c(User.age_).at(28)])), ['ada', 'cyd']);
      expect(await _ids(ordered.endAt((c) => [c(User.age_).at(28)])), ['bob', 'dee']);
      expect(await _ids(ordered.endBefore((c) => [c(User.age_).at(28)])), ['bob']);
      expect(await _ids(ordered.startAfter((c) => [c(User.age_).at(17)]).endAt((c) => [c(User.age_).at(36)])), [
        'dee',
        'ada',
      ]);
    });

    test('pages with cursors on descending order', () async {
      final ordered = db.users.orderBy((o) => [o.desc(User.age_)]);

      expect(await _ids(ordered.startAfter((c) => [c(User.age_).at(36)])), ['dee', 'bob']);
      expect(await _ids(ordered.endBefore((c) => [c(User.age_).at(36)])), ['cyd']);
    });

    test('pages from a document', () async {
      final ordered = db.users.orderBy((o) => [o.asc(User.age_)]);
      final last = (await ordered.limit(2).get()).docs.last;

      expect(await _ids(ordered.startAfterDocument(last)), ['ada', 'cyd']);
    });

    test('breaks a tie on the first field with the next one', () async {
      await db.users.doc('eli').set(const User(name: 'Eli', age: 36));

      final ordered = db.users.orderBy((o) => [o.asc(User.age_)]);

      expect(await _ids(ordered.startAfter((c) => [c(User.age_).at(36), c(Field.documentId).at('ada')])), [
        'eli',
        'cyd',
      ]);
    });

    test('counts, sums and averages', () async {
      expect(await db.users.count(), 4);
      expect(await db.users.where((w) => w(User.age_).isGreaterThan(20)).count(), 3);
      expect(await db.users.orderBy((o) => [o.asc(User.age_)]).limit(2).count(), 2);
      expect(await db.users.sum(User.age_), 133);
      expect(await db.users.average(User.age_), 33.25);
      expect(await db.users.where((w) => w(User.age_).isGreaterThan(100)).sum(User.age_), 0);
      expect(await db.users.where((w) => w(User.age_).isGreaterThan(100)).average(User.age_), isNull);
    });

    test('fails at the call for a condition that cannot be built', () {
      expect(() => db.users.where((w) => w(User.age_).isIn([])), throwsArgumentError);
      expect(() => db.users.where((w) => w.and([])), throwsArgumentError);
      expect(() => db.users.where((w) => w(const Field<int>("a'b")).isEqualTo(1)), throwsArgumentError);
      expect(() => db.users.orderBy((o) => []), throwsArgumentError);
      expect(() => db.users.limit(0), throwsArgumentError);
    });

    test('never lets a field name reach the SQL', () async {
      const hostile = Field<int>("age') OR 1=1 --");

      expect(() => db.users.where((w) => w(hostile).isEqualTo(1)), throwsArgumentError);
      expect(() => db.users.orderBy((o) => [o.asc(hostile)]), throwsArgumentError);
      expect(await db.users.count(), 4);
    });

    test('refuses a cursor that does not match the order', () {
      final ordered = db.users.orderBy((o) => [o.asc(User.age_)]);

      expect(() => ordered.startAt((c) => [c(User.name_).at('Ada')]), throwsStateError);
      expect(() => ordered.startAt((c) => [c(User.age_).at(1), c(User.name_).at('x')]), throwsStateError);
      expect(() => ordered.startAt((c) => []), throwsArgumentError);
      expect(() => db.users.startAt((c) => [c(User.age_).at(1)]), throwsStateError);
    });

    test('a query does not change the one it was built from', () async {
      final base = db.users.where((w) => w(User.age_).isGreaterThan(20));
      base.orderBy((o) => [o.asc(User.age_)]).limit(1);

      expect(await _ids(base), ['ada', 'cyd', 'dee']);
    });
  });

  group('Collection.clear and drop', () {
    setUp(() => _seed(db));

    test('clear removes every document and keeps the table', () async {
      await db.users.clear();

      expect(await db.users.count(), 0);
      expect(await AppStorage.tableExists('users'), isTrue);
    });

    test('drop removes the table, and the collection still works afterwards', () async {
      await db.users.drop();

      expect(await AppStorage.tableExists('users'), isFalse);
      await db.users.doc('ada').set(const User(name: 'Ada', age: 36));
      expect(await db.users.count(), 1);
    });

    test('drop tells a listener the collection emptied out', () async {
      final emitted = <int>[];
      final subscription = db.users.snapshots().listen((s) => emitted.add(s.size));
      await _waitFor(emitted, 1);

      await db.users.drop();
      await _waitFor(emitted, 2);
      await subscription.cancel();

      expect(emitted, [4, 0]);
    });

    test('drop refuses a table that is not the collection\'s own', () async {
      await AppStorage.execute('CREATE TABLE foreign_table (a TEXT, b TEXT)');

      await expectLater(Collection<User>('foreign_table', User.fromJson).drop(), throwsA(isA<StateError>()));
      expect(await AppStorage.tableExists('foreign_table'), isTrue);
    });
  });

  group('FieldValue in toJson', () {
    test('resolves against nothing when creating or replacing', () async {
      await db.visits.doc('home').set(const Visit());
      final snapshot = await db.visits.doc('home').get();

      expect(snapshot.data()!.hits, 1);
      expect(DateTime.tryParse(snapshot.data()!.seen!), isNotNull);
      expect(snapshot.get(Visit.note_), isNull);
      expect(snapshot.get(Visit.nestedCount_), 2);
    });

    test('resolves against the stored document when merging', () async {
      await db.visits.doc('home').set(const Visit());
      await db.visits.doc('home').set(const Visit(), merge: true);
      await db.visits.doc('home').set(const Visit(), merge: true);

      final snapshot = await db.visits.doc('home').get();
      expect(snapshot.data()!.hits, 3);
      expect(snapshot.get(Visit.nestedCount_), 6);
    });

    test('a replace starts over instead of accumulating', () async {
      await db.visits.doc('home').set(const Visit());
      await db.visits.doc('home').set(const Visit());

      expect((await db.visits.doc('home').get()).data()!.hits, 1);
    });

    test('works through add, a batch and a transaction', () async {
      final added = await db.visits.add(const Visit());
      await (db.batch()..set(db.visits.doc('b'), const Visit())).commit();
      await db.runTransaction((tx) => tx.set(db.visits.doc('t'), const Visit()));

      expect((await added.get()).data()!.hits, 1);
      expect((await db.visits.doc('b').get()).data()!.hits, 1);
      expect((await db.visits.doc('t').get()).data()!.hits, 1);
    });
  });

  group('update through a batch and a transaction', () {
    test('takes the same typed builder', () async {
      await db.users.doc('ada').set(const User(name: 'Ada', age: 36, city: 'London'));

      await (db.batch()..update(db.users.doc('ada'), (u) => [u(User.age_).set(40)])).commit();
      await db.runTransaction((tx) => tx.update(db.users.doc('ada'), (u) => [u(User.city_).set('Paris')]));

      final user = (await db.users.doc('ada').get()).data()!;
      expect((user.age, user.city), (40, 'Paris'));
    });

    test('refuses the document id as a field to change', () async {
      await db.users.doc('ada').set(const User(name: 'Ada', age: 36));

      await expectLater(db.users.doc('ada').update((u) => [u(Field.documentId).set('x')]), throwsArgumentError);
    });
  });

  group('Tenant', () {
    const ada = User(name: 'Ada', age: 36);
    const bob = User(name: 'Bob', age: 17);

    Future<String?> nameOf(String id) async => (await db.users.doc(id).get()).data()?.name;

    test('is isolated by default', () {
      expect(db.users.tunnel, Tunnel.isolated);
    });

    test('keeps two tenants apart, even under the same id and with the same content', () async {
      Tenant.use('a');
      await db.users.doc('u1').set(ada);
      Tenant.use('b');

      expect(await nameOf('u1'), isNull);
      await db.users.doc('u1').set(ada);
      await db.users.doc('u1').update((u) => [u(User.age_).set(99)]);
      Tenant.use('a');

      expect((await db.users.doc('u1').get()).data()!.age, 36);
    });

    test('scopes queries, counts and aggregates to the current tenant', () async {
      Tenant.use('a');
      await db.users.doc('x').set(ada);
      await db.users.doc('y').set(bob);
      Tenant.use('b');
      await db.users.doc('z').set(const User(name: 'Zed', age: 50));

      expect(await _ids(db.users), ['z']);
      expect(await _ids(db.users.where((w) => w(User.age_).isGreaterThan(0))), ['z']);
      expect(await db.users.count(), 1);
      expect(await db.users.sum(User.age_), 50);
      Tenant.use('a');
      expect(await _ids(db.users), ['x', 'y']);
    });

    test('never shows the previous account after leaving it', () async {
      Tenant.use('a');
      await db.users.doc('x').set(ada);

      Tenant.leave();

      expect(await _ids(db.users), isEmpty);
      await db.users.doc('guest').set(bob);
      Tenant.use('a');
      expect(await _ids(db.users), ['x']);
    });

    test('refuses an empty tenant id', () {
      expect(() => Tenant.use(''), throwsArgumentError);
      expect(() => db.users.inTenant(''), throwsArgumentError);
      expect(() => db.users.acrossTenants(only: ['']), throwsArgumentError);
    });

    test('reports its changes', () async {
      final seen = <String?>[];
      final subscription = Tenant.changes.listen(seen.add);

      Tenant.use('a');
      Tenant.use('a');
      Tenant.leave();
      Tenant.leave();
      await pumpEventQueue();
      await subscription.cancel();

      expect(seen, ['a', null]);
      expect(Tenant.current, isNull);
    });

    test('lets a shared collection ignore the tenant', () async {
      Tenant.use('a');
      await db.catalogue.doc('c1').set(Item(label: 'pen', stock: 1, addedAt: DateTime.utc(2026)));
      Tenant.use('b');

      expect((await db.catalogue.doc('c1').get()).exists, isTrue);
      expect(await db.catalogue.count(), 1);
    });

    test('has no tenants to reach into on a shared collection', () {
      expect(() => db.catalogue.inTenant('a'), throwsStateError);
      expect(() => db.catalogue.acrossTenants(), throwsStateError);
    });

    test('finishes an operation on the tenant it started on', () async {
      Tenant.use('a');
      final pending = db.users.doc('x').set(ada);
      Tenant.use('b');
      await pending;

      expect(await nameOf('x'), isNull);
      Tenant.use('a');
      expect(await nameOf('x'), 'Ada');
    });

    test('commits a batch on the tenant each write was queued on', () async {
      Tenant.use('a');
      final batch = db.batch()..set(db.users.doc('x'), ada);
      Tenant.use('b');
      batch.set(db.users.doc('x'), bob);
      Tenant.leave();
      await batch.commit();

      Tenant.use('a');
      expect(await nameOf('x'), 'Ada');
      Tenant.use('b');
      expect(await nameOf('x'), 'Bob');
      Tenant.leave();
      expect(await nameOf('x'), isNull);
    });

    test('runs a transaction on the tenant current at each call', () async {
      Tenant.use('a');
      await db.runTransaction((tx) async {
        await tx.set(db.users.doc('x'), ada);
        expect((await tx.get(db.users.doc('x'))).exists, isTrue);
      });

      Tenant.use('b');
      expect(await nameOf('x'), isNull);
    });

    test('clears only the current tenant', () async {
      Tenant.use('a');
      await db.users.doc('x').set(ada);
      Tenant.use('b');
      await db.users.doc('x').set(bob);

      await db.users.clear();

      expect(await db.users.count(), 0);
      Tenant.use('a');
      expect(await db.users.count(), 1);
    });

    test('drops the table for every tenant', () async {
      Tenant.use('a');
      await db.users.doc('x').set(ada);

      await db.users.drop();

      Tenant.use('b');
      expect(await db.users.count(), 0);
      Tenant.use('a');
      expect(await db.users.count(), 0);
    });

    test('refuses a reserved collection name', () {
      expect(() => Collection<User>('pylon_x', User.fromJson), throwsArgumentError);
    });
  });

  group('Tenant.inTenant', () {
    test('reads and writes another tenant directly', () async {
      Tenant.use('a');
      await db.users.inTenant('b').doc('x').set(const User(name: 'Bob', age: 17));

      expect((await db.users.doc('x').get()).exists, isFalse);
      expect((await db.users.inTenant('b').doc('x').get()).data()!.name, 'Bob');
      expect(await _ids(db.users.inTenant('b').where((w) => w(User.age_).isLessThan(18))), ['x']);
      Tenant.use('b');
      expect((await db.users.doc('x').get()).data()!.name, 'Bob');
    });

    test('is not moved by a change of the current tenant', () async {
      final b = db.users.inTenant('b');
      Tenant.use('a');
      await b.doc('x').set(const User(name: 'Bob', age: 17));
      Tenant.use('c');

      expect((await b.doc('x').get()).exists, isTrue);
      expect(await b.count(), 1);
    });

    test('a pinned reference is not equal to the current one', () {
      expect(db.users.inTenant('a').doc('x'), db.users.inTenant('a').doc('x'));
      expect(db.users.inTenant('a').doc('x'), isNot(db.users.doc('x')));
    });
  });

  group('Tenant.acrossTenants', () {
    setUp(() async {
      await db.users.inTenant('a').doc('u1').set(const User(name: 'Ada', age: 36));
      await db.users.inTenant('b').doc('u1').set(const User(name: 'Bea', age: 20));
      await db.users.inTenant('b').doc('u2').set(const User(name: 'Bob', age: 17));
      await db.users.doc('guest').set(const User(name: 'Guest', age: 1));
    });

    test('brings back every tenant, the same id once per tenant', () async {
      final snapshot = await db.users.acrossTenants().get();

      expect(snapshot.docs.map((d) => (d.tenant, d.id)), [(null, 'guest'), ('a', 'u1'), ('b', 'u1'), ('b', 'u2')]);
    });

    test('can be narrowed to some tenants', () async {
      final snapshot = await db.users.acrossTenants(only: ['a', 'b']).get();

      expect(snapshot.docs.map((d) => d.tenant), ['a', 'b', 'b']);
    });

    test('filters, orders and counts across tenants', () async {
      final adults = db.users
          .acrossTenants()
          .where((w) => w(User.age_).isGreaterThan(18))
          .orderBy((o) => [o.asc(User.age_)]);

      expect((await adults.get()).items.map((u) => u.name), ['Bea', 'Ada']);
      expect(await db.users.acrossTenants().count(), 4);
      expect(await db.users.acrossTenants().sum(User.age_), 74);
    });

    test('hands out references that write to the right tenant', () async {
      final bea =
          (await db.users.acrossTenants(only: ['b']).where((w) => w(User.age_).isEqualTo(20)).get()).docs.single;

      await bea.reference.update((u) => [u(User.age_).set(21)]);

      expect((await db.users.inTenant('b').doc('u1').get()).data()!.age, 21);
      expect((await db.users.inTenant('a').doc('u1').get()).data()!.age, 36);
    });

    test('has no cursors', () async {
      final ordered = db.users.acrossTenants().orderBy((o) => [o.asc(User.age_)]);

      await expectLater(ordered.startAfter((c) => [c(User.age_).at(1)]).get(), throwsA(isA<StateError>()));
    });

    test('follows writes to any tenant', () async {
      final emitted = <QuerySnapshot<User>>[];
      final subscription = db.users.acrossTenants().snapshots().listen(emitted.add);
      await _waitFor(emitted, 1);

      await db.users.inTenant('c').doc('u9').set(const User(name: 'Cy', age: 5));
      await _waitFor(emitted, 2);
      await subscription.cancel();

      expect(emitted[1].docChanges.single.doc.tenant, 'c');
    });
  });

  group('Tenant and snapshots', () {
    test('a query is handed the new tenant\'s documents from scratch', () async {
      await db.users.inTenant('a').doc('ada').set(const User(name: 'Ada', age: 36));
      await db.users.inTenant('b').doc('bob').set(const User(name: 'Bob', age: 17));
      Tenant.use('a');
      final emitted = <QuerySnapshot<User>>[];
      final subscription = db.users.snapshots().listen(emitted.add);
      await _waitFor(emitted, 1);

      Tenant.use('b');
      await _waitFor(emitted, 2);

      expect(emitted[0].items.map((u) => u.name), ['Ada']);
      expect(emitted[1].items.map((u) => u.name), ['Bob']);
      expect(emitted[1].docChanges.map((c) => (c.type, c.doc.id)), [(DocumentChangeType.added, 'bob')]);

      await db.users.inTenant('a').doc('more').set(const User(name: 'More', age: 1));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await subscription.cancel();
      expect(emitted, hasLength(2));
    });

    test('a query on a shared collection ignores a change of tenant', () async {
      await db.catalogue.doc('c1').set(Item(label: 'pen', stock: 1, addedAt: DateTime.utc(2026)));
      final emitted = <int>[];
      final subscription = db.catalogue.snapshots().listen((s) => emitted.add(s.size));
      await _waitFor(emitted, 1);

      Tenant.use('a');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await subscription.cancel();

      expect(emitted, [1]);
    });

    test('a pinned query does not follow the current tenant', () async {
      await db.users.inTenant('b').doc('bob').set(const User(name: 'Bob', age: 17));
      final emitted = <int>[];
      final subscription = db.users.inTenant('b').snapshots().listen((s) => emitted.add(s.size));
      await _waitFor(emitted, 1);

      Tenant.use('a');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await subscription.cancel();

      expect(emitted, [1]);
    });

    test('a document follows the tenant too', () async {
      await db.users.inTenant('a').doc('u1').set(const User(name: 'Ada', age: 36));
      Tenant.use('a');
      final emitted = <String?>[];
      final subscription = db.users.doc('u1').snapshots().listen((s) => emitted.add(s.data()?.name));
      await _waitFor(emitted, 1);

      Tenant.use('b');
      await _waitFor(emitted, 2);
      await subscription.cancel();

      expect(emitted, ['Ada', null]);
    });
  });

  group('Tenant.list, purge and transfer', () {
    setUp(() async {
      await db.users.inTenant('a').doc('u1').set(const User(name: 'Ada', age: 36));
      await db.users.inTenant('a').doc('u2').set(const User(name: 'Al', age: 40));
      await db.users.inTenant('b').doc('u1').set(const User(name: 'Bea', age: 20));
      await db.users.doc('guest').set(const User(name: 'Guest', age: 1));
      await db.items.inTenant('a').doc('i1').set(Item(label: 'pen', stock: 1, addedAt: DateTime.utc(2026)));
      await db.catalogue.doc('c1').set(Item(label: 'shared', stock: 1, addedAt: DateTime.utc(2026)));
    });

    test('lists the tenants that hold documents, not the anonymous ones', () async {
      expect(await Tenant.list(), ['a', 'b']);
    });

    test('purges one tenant from every isolated collection and nothing else', () async {
      await Tenant.purge('a');

      expect(await Tenant.list(), ['b']);
      expect(await db.users.inTenant('b').count(), 1);
      expect(await db.items.inTenant('a').count(), 0);
      expect(await db.users.count(), 1);
      expect(await db.catalogue.count(), 1);
    });

    test('a purge is heard by listeners', () async {
      Tenant.use('a');
      final emitted = <int>[];
      final subscription = db.users.snapshots().listen((s) => emitted.add(s.size));
      await _waitFor(emitted, 1);

      await Tenant.purge('a');
      await _waitFor(emitted, 2);
      await subscription.cancel();

      expect(emitted, [2, 0]);
    });

    test('carries the anonymous documents over to an account', () async {
      final moved = await Tenant.transfer(to: 'a');

      expect(moved, 1);
      expect(await db.users.count(), 0);
      expect(await _ids(db.users.inTenant('a')), ['guest', 'u1', 'u2']);
      expect(await db.catalogue.count(), 1);
    });

    test('keeps the target\'s document on a conflict by default', () async {
      final moved = await Tenant.transfer(from: 'b', to: 'a');

      expect(moved, 0);
      expect((await db.users.inTenant('a').doc('u1').get()).data()!.name, 'Ada');
      expect(await db.users.inTenant('b').count(), 0);
    });

    test('lets the source win on request', () async {
      final moved = await Tenant.transfer(from: 'b', to: 'a', onConflict: TransferConflict.keepSource);

      expect(moved, 1);
      expect((await db.users.inTenant('a').doc('u1').get()).data()!.name, 'Bea');
      expect(await db.users.inTenant('b').count(), 0);
    });

    test('counts what moved across every collection', () async {
      final moved = await Tenant.transfer(from: 'a', to: 'c');

      expect(moved, 3);
    });

    test('refuses to move a tenant onto itself', () async {
      await expectLater(Tenant.transfer(from: 'a', to: 'a'), throwsArgumentError);
      await expectLater(Tenant.transfer(), throwsArgumentError);
    });

    test('forgets a dropped collection', () async {
      await db.items.drop();
      await Tenant.purge('a');

      expect(await AppStorage.tableExists('items'), isFalse);
      expect(await db.users.inTenant('a').count(), 0);
    });
  });

  group('tables made before tenants existed', () {
    test('are rebuilt with their documents in the anonymous partition', () async {
      await AppStorage.execute(
        'CREATE TABLE users (id TEXT PRIMARY KEY NOT NULL, data TEXT NOT NULL, '
        'created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
      );
      await AppStorage.execute('INSERT INTO users VALUES (?, ?, 1, 2)', [
        const DatabaseType.varchar('old'),
        const DatabaseType.varchar('{"name":"Old","age":70}'),
      ]);

      final snapshot = await db.users.doc('old').get();

      expect(snapshot.data()!.name, 'Old');
      expect(snapshot.createTime, DateTime.fromMillisecondsSinceEpoch(1, isUtc: true));
      Tenant.use('a');
      expect((await db.users.doc('old').get()).exists, isFalse);
      final columns = await AppStorage.columns('users');
      expect(columns.map((c) => c.name), containsAll(['tenant', 'id', 'data']));
    });
  });

  group('typed fields', () {
    setUp(() => _seed(db));

    test('filter and order without a single string', () async {
      final query = db.users
          .where((w) => w(User.age_).isGreaterThan(20))
          .where((w) => w(User.city_).isEqualTo('Paris'))
          .orderBy((o) => [o.asc(User.age_)]);

      expect(await _ids(query), ['cyd']);
    });

    test('offer every comparison', () async {
      expect(await _ids(db.users.where((w) => w(User.age_).isNotEqualTo(17))), ['ada', 'cyd', 'dee']);
      expect(await _ids(db.users.where((w) => w(User.age_).isLessThanOrEqualTo(28))), ['bob', 'dee']);
      expect(await _ids(db.users.where((w) => w(User.age_).isGreaterThanOrEqualTo(36))), ['ada', 'cyd']);
      expect(await _ids(db.users.where((w) => w(User.age_).isLessThan(28))), ['bob']);
      expect(await _ids(db.users.where((w) => w(User.age_).isNotIn([17, 28]))), ['ada', 'cyd']);
      expect(await _ids(db.users.where((w) => w(User.city_).isNull())), ['dee']);
      expect(await _ids(db.users.where((w) => w(User.city_).isNotNull())), ['ada', 'bob', 'cyd']);
    });

    test('offer isBetween, both ends included', () async {
      expect(await _ids(db.users.where((w) => w(User.age_).isBetween(17, 36))), ['ada', 'bob', 'dee']);
      expect(await _ids(db.users.where((w) => w(User.name_).isBetween('Bob', 'Cyd'))), ['bob', 'cyd']);
    });

    test('filter on a list', () async {
      expect(await _ids(db.users.where((w) => w.list(User.tags_).arrayContains('code'))), ['ada', 'bob']);
      expect(await _ids(db.users.where((w) => w.list(User.tags_).arrayContainsAny(['art', 'math']))), ['ada', 'cyd']);
    });

    test('paginate on a typed order, in both directions', () async {
      final descending = db.users.orderBy((o) => [o.desc(User.age_)]);

      expect(await _ids(descending.startAfter((c) => [c(User.age_).at(36)])), ['dee', 'bob']);
      expect(await _ids(descending.endBefore((c) => [c(User.age_).at(36)])), ['cyd']);
    });

    test('aggregate only over numeric fields', () async {
      expect(await db.users.sum(User.age_), 133);
      expect(await db.users.average(User.age_), 33.25);
    });

    test('order by the document id', () async {
      expect(await _ids(db.users.orderBy((o) => [o.desc(Field.documentId)])), ['dee', 'cyd', 'bob', 'ada']);
    });
  });

  group('snapshots', () {
    test('a query emits its first result, then each change', () async {
      await db.users.doc('ada').set(const User(name: 'Ada', age: 36));
      final emitted = <QuerySnapshot<User>>[];
      final subscription = db.users
          .where((w) => w(User.age_).isGreaterThan(20))
          .orderBy((o) => [o.asc(User.age_)])
          .snapshots()
          .listen(emitted.add);
      await _waitFor(emitted, 1);

      await db.users.doc('bob').set(const User(name: 'Bob', age: 17));
      await db.users.doc('cyd').set(const User(name: 'Cyd', age: 52));
      await _waitFor(emitted, 2);
      await db.users.doc('ada').update((u) => [u(User.age_).set(40)]);
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
      await db.users.doc('ada').set(const User(name: 'Ada', age: 36));
      final emitted = <QuerySnapshot<User>>[];
      final subscription = db.users.where((w) => w(User.age_).isGreaterThan(20)).snapshots().listen(emitted.add);
      await _waitFor(emitted, 1);

      await db.users.doc('bob').set(const User(name: 'Bob', age: 17));
      await db.users.doc('cyd').set(const User(name: 'Cyd', age: 52));
      await _waitFor(emitted, 2);
      await subscription.cancel();

      expect(emitted, hasLength(2));
      expect(emitted[1].docChanges.map((c) => c.doc.id), ['cyd']);
    });

    test('a moved document is a modification, a shifted one is not', () async {
      await _seed(db);
      final emitted = <QuerySnapshot<User>>[];
      final subscription = db.users.orderBy((o) => [o.asc(User.age_)]).snapshots().listen(emitted.add);
      await _waitFor(emitted, 1);

      await db.users.doc('bob').delete();
      await _waitFor(emitted, 2);
      await db.users.doc('dee').update((u) => [u(User.age_).set(60)]);
      await _waitFor(emitted, 3);
      await subscription.cancel();

      expect(emitted[1].docChanges.map((c) => (c.type, c.doc.id)), [(DocumentChangeType.removed, 'bob')]);
      expect(emitted[2].docChanges.map((c) => (c.type, c.doc.id)), [(DocumentChangeType.modified, 'dee')]);
    });

    test('a document emits on create, change and delete', () async {
      final emitted = <User?>[];
      final subscription = db.users.doc('ada').snapshots().listen((s) => emitted.add(s.data()));
      await _waitFor(emitted, 1);

      await db.users.doc('ada').set(const User(name: 'Ada', age: 36));
      await _waitFor(emitted, 2);
      await db.users.doc('ada').update((u) => [u(User.age_).set(37)]);
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
            ..set(db.users.doc('a'), const User(name: 'A', age: 1))
            ..set(db.users.doc('b'), const User(name: 'B', age: 2)))
          .commit();
      await _waitFor(emitted, 2);
      await db.runTransaction((tx) => tx.set(db.users.doc('c'), const User(name: 'C', age: 3)));
      await _waitFor(emitted, 3);
      await subscription.cancel();

      expect(emitted, [0, 2, 3]);
    });

    test('stops reading once cancelled', () async {
      final emitted = <int>[];
      final subscription = db.users.snapshots().listen((s) => emitted.add(s.size));
      await _waitFor(emitted, 1);
      await subscription.cancel();

      await db.users.doc('a').set(const User(name: 'A', age: 1));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(emitted, [0]);
    });
  });

  group('WriteBatch', () {
    test('applies every write together', () async {
      await db.users.doc('gone').set(const User(name: 'Gone', age: 1));
      await db.items.doc('i1').set(Item(label: 'pen', stock: 5, addedAt: DateTime.utc(2026)));

      await (db.batch()
            ..set(db.users.doc('ada'), const User(name: 'Ada', age: 36))
            ..update(db.items.doc('i1'), (u) => [u(Item.stock_).increment(-1)])
            ..delete(db.users.doc('gone')))
          .commit();

      expect((await db.users.doc('ada').get()).exists, isTrue);
      expect((await db.items.doc('i1').get()).data()!.stock, 4);
      expect((await db.users.doc('gone').get()).exists, isFalse);
    });

    test('applies none of them when one fails', () async {
      await db.users.doc('ada').get();

      final batch = db.batch()
        ..set(db.users.doc('ok'), const User(name: 'Ok', age: 1))
        ..update(db.users.doc('missing'), (u) => [u(User.age_).set(2)]);

      await expectLater(batch.commit(), throwsA(isA<DocumentNotFoundError>()));
      expect((await db.users.doc('ok').get()).exists, isFalse);
    });

    test('commits once', () async {
      final batch = db.batch()..set(db.users.doc('a'), const User(name: 'A', age: 1));
      await batch.commit();

      expect(batch.commit, throwsStateError);
      expect(() => batch.delete(db.users.doc('a')), throwsStateError);
    });
  });

  group('runTransaction', () {
    test('reads what it wrote and commits together', () async {
      await db.items.doc('i1').set(Item(label: 'pen', stock: 5, addedAt: DateTime.utc(2026)));

      final remaining = await db.runTransaction((tx) async {
        final item = (await tx.get(db.items.doc('i1'))).data()!;
        await tx.update(db.items.doc('i1'), (u) => [u(Item.stock_).set(item.stock - 2)]);
        await tx.set(db.users.doc('buyer'), const User(name: 'Buyer', age: 30));
        return (await tx.get(db.items.doc('i1'))).data()!.stock;
      });

      expect(remaining, 3);
      expect((await db.users.doc('buyer').get()).exists, isTrue);
    });

    test('rolls everything back when the action throws', () async {
      await expectLater(
        db.runTransaction((tx) async {
          await tx.set(db.users.doc('a'), const User(name: 'A', age: 1));
          throw StateError('nope');
        }),
        throwsStateError,
      );

      expect((await db.users.doc('a').get()).exists, isFalse);
    });

    test('creates the table of a collection it is the first to touch', () async {
      await db.runTransaction(
        (tx) => tx.set(db.items.doc('i1'), Item(label: 'pen', stock: 1, addedAt: DateTime.utc(2026))),
      );

      expect((await db.items.doc('i1').get()).exists, isTrue);
    });
  });
}
