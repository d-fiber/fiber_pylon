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

// A schema-validation check like test/typed_database_test.dart: an increment is
// only proven by real concurrent writes to a real SQLite file.

import 'dart:io';

import 'package:fiber_pylon/src/sdk/clients/local/database/engine/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

final class Counter {
  const Counter({this.id, required this.name, this.hits = 0, this.score, this.balance = 0.0});

  final int? id;
  final String name;
  final int hits;
  final int? score;
  final double balance;
}

final class Counters extends KeyedTable<Counter, int> {
  Counters() : super('counters');

  late final id = column.key();
  late final name = column.text('name');
  late final hits = column.integer('hits').defaultsTo(0);
  late final score = column.integer('score').nullable();
  late final balance = column.real('balance').defaultsTo(0.0);

  @override
  Tunnel get tunnel => Tunnel.isolated;

  @override
  List<Field<Object?>> get columns => [id, name, hits, score, balance];

  @override
  Counter read(Reader row) =>
      Counter(id: row(id), name: row(name), hits: row(hits), score: row(score), balance: row(balance));

  @override
  List<Assignment> write(Counter c) => [
    id.toOrGenerate(c.id),
    name.to(c.name),
    hits.to(c.hits),
    score.to(c.score),
    balance.to(c.balance),
  ];
}

/// Writes an increment where only a set is possible.
final class Wrong extends KeyedTable<Counter, int> {
  Wrong(this.counters) : super('counters');

  final Counters counters;

  late final id = column.key();
  late final name = column.text('name');
  late final hits = column.integer('hits').defaultsTo(0);

  @override
  List<Field<Object?>> get columns => [id, name, hits];

  @override
  Counter read(Reader row) => Counter(id: row(id), name: row(name), hits: row(hits));

  @override
  List<Assignment> write(Counter c) => [id.toOrGenerate(c.id), name.to(c.name), hits.incrementBy(1)];
}

void main() {
  late Directory directory;
  late Counters counters;
  late LocalDatabase db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    Tenant.leave();
    directory = await Directory.systemTemp.createTemp('pylon_increment');
    databaseFactoryFfi.setDatabasesPath(directory.path);
    counters = Counters();
    db = LocalDatabase.declared(name: 'increment.db', tables: [counters]);
    await db.open();
  });

  tearDown(() async {
    Tenant.leave();
    await db.dispose();
    await directory.delete(recursive: true);
  });

  Future<Counter> only() async => (await counters.on(db).list()).single;

  group('incrementBy', () {
    test('adds to what the column holds, and subtracts a negative amount', () async {
      final made = await counters.on(db).insert(const Counter(name: 'a', hits: 10));

      await counters.on(db).where(counters.id.isEqualTo(made.id!)).update([counters.hits.incrementBy(5)]);
      expect((await only()).hits, 15);
      await counters.on(db).where(counters.id.isEqualTo(made.id!)).update([counters.hits.incrementBy(-20)]);

      expect((await only()).hits, -5);
    });

    test('counts a NULL as zero', () async {
      await counters.on(db).insert(const Counter(name: 'a'));

      await counters.on(db).updateAll([counters.score.incrementBy(3)]);

      expect((await only()).score, 3);
    });

    test('adds real numbers to a real column', () async {
      await counters.on(db).insert(const Counter(name: 'a', balance: 1.5));

      await counters.on(db).updateAll([counters.balance.incrementBy(0.25)]);

      expect((await only()).balance, 1.75);
    });

    test('goes with an ordinary assignment in the same update', () async {
      await counters.on(db).insert(const Counter(name: 'a', hits: 1));

      await counters.on(db).updateAll([counters.name.to('b'), counters.hits.incrementBy(1)]);

      final counter = await only();
      expect((counter.name, counter.hits), ('b', 2));
    });

    test('loses none of fifty updates made at once', () async {
      await counters.on(db).insert(const Counter(name: 'a'));

      await Future.wait([
        for (var i = 0; i < 50; i++) counters.on(db).updateAll([counters.hits.incrementBy(1)]),
      ]);

      expect((await only()).hits, 50);
    });

    test('changes only the rows a filter keeps', () async {
      await counters.on(db).insertAll(const [Counter(name: 'a'), Counter(name: 'b')]);

      final changed = await counters.on(db).where(counters.name.isEqualTo('b')).update([counters.hits.incrementBy(7)]);

      expect(changed, 1);
      final rows = await counters.on(db).orderBy([counters.name.asc()]).list();
      expect(rows.map((c) => c.hits), [0, 7]);
    });

    test('changes only the current tenant\'s rows', () async {
      Tenant.use('a');
      await counters.on(db).insert(const Counter(name: 'mine'));
      Tenant.use('b');
      await counters.on(db).insert(const Counter(name: 'theirs'));

      await counters.on(db).updateAll([counters.hits.incrementBy(1)]);

      expect((await only()).hits, 1);
      Tenant.use('a');
      expect((await only()).hits, 0);
    });

    test('is heard by a watcher', () async {
      await counters.on(db).insert(const Counter(name: 'a'));
      final seen = <int>[];
      final subscription = counters.on(db).watch().listen((rows) => seen.add(rows.single.hits));
      while (seen.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      await counters.on(db).updateAll([counters.hits.incrementBy(2)]);
      while (seen.length < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await subscription.cancel();

      expect(seen, [0, 2]);
    });

    test('is refused by an insert and by an upsert, which have nothing to add to', () async {
      final wrong = Wrong(counters);

      await expectLater(db.transaction((txn) => wrong.on(txn).insert(const Counter(name: 'x'))), throwsStateError);
    });

    test('is refused twice on one column in one update', () async {
      await counters.on(db).insert(const Counter(name: 'a'));

      await expectLater(
        counters.on(db).updateAll([counters.hits.incrementBy(1), counters.hits.to(5)]),
        throwsStateError,
      );
    });
  });
}
