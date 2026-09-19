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

import 'package:fiber_pylon/fiber_pylon.dart';
import 'package:fiber_pylon/src/sdk/clients/local/database/engine/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

final class Note implements Storable {
  const Note(this.body);

  final String body;

  @override
  RawRow toRow() => {'body': Value.varchar(body)};
}

final class NoColumns implements Storable {
  const NoColumns();

  @override
  RawRow toRow() => {};
}

final class Spaced implements Storable {
  const Spaced(this.value);

  final int value;

  @override
  RawRow toRow() => {'my col': Value.integer(value)};
}

final class Cells implements Storable {
  const Cells(this.n, this.g);

  final int n;
  final String g;

  @override
  RawRow toRow() => {'n': Value.integer(n), 'g': Value.varchar(g)};
}

const String _notes = 'CREATE TABLE notes (id INTEGER PRIMARY KEY AUTOINCREMENT, body TEXT NOT NULL DEFAULT \'\')';
const String _cells = 'CREATE TABLE cells (id INTEGER PRIMARY KEY AUTOINCREMENT, n INTEGER NOT NULL, g TEXT NOT NULL)';

void main() {
  late Directory directory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pylon_local_database_faults');
    databaseFactoryFfi.setDatabasesPath(directory.path);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  Future<LocalDatabase> openWith(
    String name,
    List<String> statements, {
    bool singleInstance = true,
    OnDatabaseConfigureFn? onConfigure,
  }) async {
    final db = LocalDatabase(
      name: name,
      singleInstance: singleInstance,
      onConfigure: onConfigure,
      onCreate: (database, version) async {
        for (final statement in statements) {
          await database.execute(statement);
        }
      },
    );
    await db.open();
    return db;
  }

  Future<int> countOf(LocalDatabase db, String table) async {
    final rows = await db.runRawQuery('SELECT COUNT(*) AS total FROM "$table"');
    return rows.single['total']!.asInt;
  }

  Future<void> fillCells(LocalDatabase db) async {
    for (final (n, g) in [(1, 'a'), (2, 'a'), (3, 'b'), (4, 'b'), (5, 'a')]) {
      await db.runInsert<Cells>((i) => i.into('cells').values(Cells(n, g)));
    }
  }

  Future<List<int>> readNs(LocalDatabase db, QueryFrom<int> Function(QueryFrom<int> query) refine) =>
      db.runQuery<int>((q) => refine(q.from('cells').map((row) => row['n']!.asInt)));

  group('LocalDatabase transactions', () {
    test('runs a write made through the database inside the transaction instead of deadlocking', () async {
      final db = await openWith('txn_join.db', [_notes]);

      await expectLater(
        db
            .runTransaction((txn) async {
              await txn.insert<Note>((i) => i.into('notes').values(const Note('through the transaction')));
              await db.runInsert<Note>((i) => i.into('notes').values(const Note('through the database')));
            })
            .timeout(const Duration(seconds: 2)),
        completes,
        reason: 'the database must not wait for a transaction that waits for it',
      );
      expect(await countOf(db, 'notes'), 2);
      await db.dispose();
    });

    test('rolls back a write made through the database when the transaction throws', () async {
      final db = await openWith('txn_rollback.db', [_notes]);

      await expectLater(
        db
            .runTransaction((txn) async {
              await db.runInsert<Note>((i) => i.into('notes').values(const Note('through the database')));
              throw StateError('abort');
            })
            .timeout(const Duration(seconds: 2)),
        throwsStateError,
      );
      expect(await countOf(db, 'notes'), 0, reason: 'a write inside a transaction that fails is not kept');
      await db.dispose();
    });

    test('joins a transaction opened inside another one instead of deadlocking', () async {
      final db = await openWith('txn_nested.db', [_notes]);

      final answer = db
          .runTransaction((outer) async {
            await outer.insert<Note>((i) => i.into('notes').values(const Note('outer')));
            return db.runTransaction((inner) async {
              await inner.insert<Note>((i) => i.into('notes').values(const Note('inner')));
              return 7;
            });
          })
          .timeout(const Duration(seconds: 2));

      await expectLater(answer, completion(7));
      expect(await countOf(db, 'notes'), 2);
      await db.dispose();
    });

    test('queues a batch created inside a transaction into that transaction', () async {
      final db = await openWith('txn_batch.db', [_notes]);

      await expectLater(
        db
            .runTransaction((txn) async {
              final batch = db.newBatch();
              batch.insert<Note>((i) => i.into('notes').values(const Note('batched')));
              await batch.commit();
              throw StateError('abort');
            })
            .timeout(const Duration(seconds: 2)),
        throwsStateError,
      );
      expect(await countOf(db, 'notes'), 0, reason: 'the batch belongs to the transaction that was rolled back');
      await db.dispose();
    });

    test('leaves a transaction on another database alone', () async {
      final first = await openWith('txn_first.db', [_notes]);
      final second = await openWith('txn_second.db', [_notes]);

      await expectLater(
        first
            .runTransaction((txn) async {
              await second.runInsert<Note>((i) => i.into('notes').values(const Note('elsewhere')));
              throw StateError('abort');
            })
            .timeout(const Duration(seconds: 2)),
        throwsStateError,
      );
      expect(await countOf(second, 'notes'), 1, reason: 'the other database was never part of the transaction');
      await first.dispose();
      await second.dispose();
    });

    test('reports a transaction used after it finished as TransactionClosedError', () async {
      final db = await openWith('txn_closed.db', [_notes]);
      late TransactionScope finished;
      await db.runTransaction((txn) async {
        finished = txn;
      });

      await expectLater(
        finished.execute('SELECT 1'),
        throwsA(isA<TransactionClosedError>()),
        reason: 'a finished transaction is not an unknown failure',
      );
      await db.dispose();
    });
  });

  group('LocalDatabase error mapping', () {
    const parentAndChild = [
      'CREATE TABLE parents (id INTEGER PRIMARY KEY)',
      'CREATE TABLE children (id INTEGER PRIMARY KEY, parent_id INTEGER REFERENCES parents(id))',
    ];

    test('reports a broken foreign key as ForeignKeyConstraintError', () async {
      final db = await openWith(
        'error_foreign_key.db',
        parentAndChild,
        onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
      );

      await expectLater(
        db.runSql('INSERT INTO children (parent_id) VALUES (99)'),
        throwsA(isA<ForeignKeyConstraintError>()),
      );
      await db.dispose();
    });

    test('reports a broken CHECK as CheckConstraintError', () async {
      final db = await openWith('error_check.db', ['CREATE TABLE ages (n INTEGER CHECK (n > 0))']);

      await expectLater(db.runSql('INSERT INTO ages (n) VALUES (0)'), throwsA(isA<CheckConstraintError>()));
      await db.dispose();
    });

    test('reports a value a STRICT column refuses as DatatypeMismatchError', () async {
      final db = await openWith('error_strict.db', ['CREATE TABLE ages (n INTEGER) STRICT']);

      await expectLater(
        db.runSql('INSERT INTO ages (n) VALUES (?)', [const Value.varchar('old')]),
        throwsA(isA<DatatypeMismatchError>()),
      );
      await db.dispose();
    });

    test('reports a column that does not exist as NoSuchColumnError', () async {
      final db = await openWith('error_no_column.db', [_notes]);

      await expectLater(db.runRawQuery('SELECT missing FROM notes'), throwsA(isA<NoSuchColumnError>()));
      await expectLater(
        db.runInsert<Cells>((i) => i.into('notes').values(const Cells(1, 'a'))),
        throwsA(isA<NoSuchColumnError>()),
      );
      await db.dispose();
    });

    test('reports a filter on a column that does not exist as NoSuchColumnError', () async {
      final db = await openWith('error_no_column_filter.db', [_notes]);

      await expectLater(
        db.runQuery<int>(
          (q) => q
              .from('notes')
              .where((w) => w.isEqualTo(key: 'missing', value: const Value.integer(1)))
              .map((row) => 1),
        ),
        throwsA(isA<NoSuchColumnError>()),
      );
      await db.dispose();
    });

    test('reports a table or an index created twice as AlreadyExistsError', () async {
      final db = await openWith('error_exists.db', [_notes]);
      await db.runSql('CREATE INDEX notes_body ON notes (body)');

      await expectLater(db.runSql(_notes), throwsA(isA<AlreadyExistsError>()));
      await expectLater(
        db.runSql('CREATE INDEX notes_body ON notes (body)'),
        throwsA(isA<AlreadyExistsError>()),
      );
      await db.dispose();
    });

    test('reports a write that meets another connection lock as BusyError', () async {
      final holder = await openWith('error_busy.db', [_notes], singleInstance: false);
      final waiter = LocalDatabase(name: 'error_busy.db', singleInstance: false);
      await waiter.open();
      await holder.runSql('BEGIN IMMEDIATE');

      await expectLater(
        waiter.runInsert<Note>((i) => i.into('notes').values(const Note('blocked'))),
        throwsA(isA<BusyError>()),
      );
      await holder.runSql('ROLLBACK');
      await holder.dispose();
      await waiter.dispose();
    });

    test('reports a file that is not a database as CorruptError', () async {
      File('${directory.path}/garbage.db').writeAsBytesSync(List.filled(4096, 7));
      final db = LocalDatabase(name: 'garbage.db');

      await expectLater(db.open(), throwsA(isA<CorruptError>()));
    });

    test('reports a write that finds the file full as StorageError', () async {
      final db = await openWith('error_full.db', ['CREATE TABLE blobs (data BLOB)']);
      await db.runSql('PRAGMA max_page_count = 4');

      await expectLater(
        db.runSql('INSERT INTO blobs (data) VALUES (zeroblob(1000000))'),
        throwsA(isA<StorageError>()),
      );
      await db.dispose();
    });

    test('reports a read only open of a file that does not exist as OpenFailedError', () async {
      final db = LocalDatabase(name: 'absent.db', readOnly: true);

      await expectLater(db.open(), throwsA(isA<OpenFailedError>()));
    });

    test('still reports what it cannot classify as UnknownError', () async {
      final db = await openWith('error_unknown.db', [_notes]);

      await expectLater(db.runRawQuery('SELECT no_such_function(1)'), throwsA(isA<UnknownError>()));
      await db.dispose();
    });
  });

  group('LocalDatabase lifecycle', () {
    const parentAndChild = [
      'CREATE TABLE parents (id INTEGER PRIMARY KEY)',
      'CREATE TABLE children (id INTEGER PRIMARY KEY, parent_id INTEGER REFERENCES parents(id))',
    ];

    test('enforces a declared foreign key without being asked', () async {
      final db = await openWith('fk_default.db', parentAndChild);

      await expectLater(
        db.runSql('INSERT INTO children (parent_id) VALUES (99)'),
        throwsA(isA<StoreError>()),
        reason: 'a declared FOREIGN KEY that SQLite ignores protects nothing',
      );
      await db.dispose();
    });

    test('lets onConfigure switch foreign keys off again', () async {
      final db = await openWith(
        'fk_off.db',
        parentAndChild,
        onConfigure: (database) => database.execute('PRAGMA foreign_keys = OFF'),
      );

      await db.runSql('INSERT INTO children (parent_id) VALUES (99)');

      expect(await countOf(db, 'children'), 1);
      await db.dispose();
    });

    test('opens a read only database whose stored version differs from the requested one', () async {
      final writer = LocalDatabase(name: 'readonly_version.db', version: 3, onCreate: (d, v) => d.execute(_notes));
      await writer.open();
      await writer.runSql("INSERT INTO notes (body) VALUES ('kept')");
      await writer.dispose();

      final reader = LocalDatabase(name: 'readonly_version.db', version: 1, readOnly: true);

      await expectLater(reader.open(), completes, reason: 'a read only open cannot rewrite the stored version');
      expect(await countOf(reader, 'notes'), 1);
      await reader.dispose();
    });

    test('never runs onCreate, onUpgrade or onDowngrade on a read only database', () async {
      final writer = LocalDatabase(name: 'readonly_calls.db', version: 3, onCreate: (d, v) => d.execute(_notes));
      await writer.open();
      await writer.dispose();
      final calls = <String>[];

      final reader = LocalDatabase(
        name: 'readonly_calls.db',
        version: 5,
        readOnly: true,
        onCreate: (d, v) async => calls.add('create'),
        onUpgrade: (d, from, to) async => calls.add('upgrade'),
        onDowngrade: (d, from, to) async => calls.add('downgrade'),
      );
      await reader.open().then<void>((_) {}, onError: (Object _) {});

      expect(calls, isEmpty);
      await reader.dispose();
    });

    test('keeps the file open for another instance when one of two instances on it is disposed', () async {
      final first = await openWith('shared_file.db', [_notes]);
      final second = LocalDatabase(name: 'shared_file.db');
      await second.open();

      await first.dispose();

      expect(second.isOpen, isTrue);
      expect(await countOf(second, 'notes'), 0, reason: 'the second instance still works on the shared file');
      await second.dispose();
    });

    test('runs onConfigure once when open is called twice at the same time', () async {
      var configured = 0;
      final db = LocalDatabase(
        name: 'double_open.db',
        singleInstance: false,
        onConfigure: (database) async => configured++,
      );

      await Future.wait([db.open(), db.open()]);

      expect(configured, 1, reason: 'the second call joins the first instead of opening another connection');
      await db.dispose();
    });

    test('leaves the database closed when dispose is called right after an open that was not awaited', () async {
      final db = LocalDatabase(name: 'open_then_dispose.db');

      final opening = db.open();
      final disposing = db.dispose();
      await Future.wait([opening, disposing]);

      expect(db.isOpen, isFalse);
    });
  });

  group('StatementBatch reuse', () {
    test('does not run a statement again when the batch is committed twice', () async {
      final db = await openWith('batch_twice.db', [_notes]);
      final batch = db.newBatch();
      batch.insert<Note>((i) => i.into('notes').values(const Note('once')));

      await batch.commit();
      final second = await batch.commit();

      expect(await countOf(db, 'notes'), 1);
      expect(second, isEmpty, reason: 'a committed batch has nothing left to run');
      await db.dispose();
    });

    test('runs only the statements queued since the last commit', () async {
      final db = await openWith('batch_refill.db', [_notes]);
      final batch = db.newBatch();
      batch.insert<Note>((i) => i.into('notes').values(const Note('first')));
      await batch.commit();

      batch.insert<Note>((i) => i.into('notes').values(const Note('second')));
      final results = await batch.commit();

      expect(results, [const BatchInserted(2)]);
      expect(await countOf(db, 'notes'), 2);
      await db.dispose();
    });
  });

  group('Query builders', () {
    test('keeps only the rows every where call matches in a query', () async {
      final db = await openWith('where_query.db', [_cells]);
      await fillCells(db);

      final rows = await readNs(
        db,
        (q) => q
            .where((w) => w.isEqualTo(key: 'g', value: const Value.varchar('a')))
            .where((w) => w.isGreaterThan(key: 'n', value: const Value.integer(1)))
            .orderBy([const Sort.named('n')]),
      );

      expect(rows, [2, 5], reason: 'the second where narrows the first instead of replacing it');
      await db.dispose();
    });

    test('updates only the rows every where call matches', () async {
      final db = await openWith('where_update.db', [_cells]);
      await fillCells(db);

      final changed = await db.runUpdate<Cells>(
        (u) => u
            .table('cells')
            .set(const Cells(0, 'z'))
            .where((w) => w.isEqualTo(key: 'g', value: const Value.varchar('a')))
            .where((w) => w.isGreaterThan(key: 'n', value: const Value.integer(1))),
      );

      expect(changed, 2);
      await db.dispose();
    });

    test('deletes only the rows every where call matches', () async {
      final db = await openWith('where_delete.db', [_cells]);
      await fillCells(db);

      final removed = await db.runDelete(
        (d) => d
            .from('cells')
            .where((w) => w.isEqualTo(key: 'g', value: const Value.varchar('a')))
            .where((w) => w.isGreaterThan(key: 'n', value: const Value.integer(1))),
      );

      expect(removed, 2);
      expect(await countOf(db, 'cells'), 3);
      await db.dispose();
    });

    test('keeps only the groups every having call matches', () async {
      final db = await openWith('having_twice.db', [_cells]);
      await fillCells(db);

      final groups = await db.runQuery<String>(
        (q) => q
            .from('cells')
            .select(['g'])
            .groupBy(['g'])
            .having((w) => w.raw('COUNT(*) >= ?', [const Value.integer(3)]))
            .having((w) => w.raw('COUNT(*) < ?', [const Value.integer(10)]))
            .map((row) => row['g']!.asString),
      );

      expect(groups, ['a']);
      await db.dispose();
    });

    test('reads an empty orderBy and an empty groupBy as no clause', () async {
      final db = await openWith('empty_lists.db', [_cells]);
      await fillCells(db);

      final ordered = await readNs(db, (q) => q.orderBy([]));
      final grouped = await readNs(db, (q) => q.groupBy([]));

      expect(ordered, hasLength(5));
      expect(grouped, hasLength(5));
      await db.dispose();
    });

    test('lets a second orderBy break the ties the first one left', () async {
      final db = await openWith('order_twice.db', [_cells]);
      await fillCells(db);

      final rows = await readNs(
        db,
        (q) => q.orderBy([const Sort.named('g')]).orderBy([
          const Sort.named('n', order: SortOrder.desc),
        ]),
      );

      expect(rows, [5, 2, 1, 4, 3]);
      await db.dispose();
    });

    test('reads the columns of every select call', () async {
      final db = await openWith('select_twice.db', [_cells]);
      await fillCells(db);

      final widths = await db.runQuery<int>((q) => q.from('cells').select(['n']).select(['g']).map((row) => row.length));

      expect(widths, everyElement(2));
      await db.dispose();
    });

    test('reads a table name with a space as one name', () async {
      final db = await openWith('table_space.db', ['CREATE TABLE "my notes" (id INTEGER PRIMARY KEY, body TEXT)']);

      await db.runInsert<Note>((i) => i.into('my notes').values(const Note('spaced')));
      final bodies = await db.runQuery<String>((q) => q.from('my notes').map((row) => row['body']!.asString));
      final changed = await db.runUpdate<Note>((u) => u.table('my notes').set(const Note('changed')));
      final removed = await db.runDelete((d) => d.from('my notes'));

      expect(bodies, ['spaced']);
      expect([changed, removed], [1, 1]);
      await db.dispose();
    });

    test('reads SQL inside a table name as a name and never as a statement', () async {
      final db = await openWith('table_injection.db', [_notes]);
      await db.runInsert<Note>((i) => i.into('notes').values(const Note('kept')));

      await expectLater(db.runDelete((d) => d.from('notes WHERE 1 = 1 --')), throwsA(isA<NoSuchTableError>()));
      expect(await countOf(db, 'notes'), 1, reason: 'the injected condition removed rows');
      await db.dispose();
    });

    test('reads a column name with a space as one name when inserting', () async {
      final db = await openWith('column_space.db', ['CREATE TABLE spaced (id INTEGER PRIMARY KEY, "my col" INTEGER)']);

      await db.runInsert<Spaced>((i) => i.into('spaced').values(const Spaced(5)));
      final changed = await db.runUpdate<Spaced>((u) => u.table('spaced').set(const Spaced(6)));

      expect(changed, 1);
      final rows = await db.runRawQuery('SELECT "my col" AS value FROM spaced');
      expect(rows.single['value']!.asInt, 6);
      await db.dispose();
    });

    test('inserts a record with no columns using the defaults of the table', () async {
      final db = await openWith('insert_defaults.db', [_notes]);

      final id = await db.runInsert<NoColumns>((i) => i.into('notes').values(const NoColumns()));

      expect(id, 1);
      final rows = await db.runRawQuery('SELECT body FROM notes');
      expect(rows.single['body']!.asString, '');
      await db.dispose();
    });

    test('inserts a record with no columns through a batch too', () async {
      final db = await openWith('insert_defaults_batch.db', [_notes]);
      final batch = db.newBatch();
      batch.insert<NoColumns>((i) => i.into('notes').values(const NoColumns()));

      final results = await batch.commit();

      expect(results, [const BatchInserted(1)]);
      await db.dispose();
    });

    test('reads the columns of a table that does not exist as an empty list that tableExists explains', () async {
      final db = await openWith('columns_missing.db', [_notes]);

      expect(await db.listColumns('absent'), isEmpty);
      expect(await db.hasTable('absent'), isFalse);
      expect(await db.listColumns('notes'), isNotEmpty);
      await db.dispose();
    });

    test('refuses to match text that holds a NUL character, which SQLite reads as the end of a pattern', () async {
      const builder = FilterBuilder();

      expect(() => builder.contains(key: 'body', text: 'a\u0000b'), throwsArgumentError);
      expect(() => builder.startsWith(key: 'body', text: '\u0000'), throwsArgumentError);
      expect(() => builder.endsWith(key: 'body', text: '\u0000'), throwsArgumentError);
      expect(() => builder.isLike(key: 'body', pattern: 'a\u0000%'), throwsArgumentError);
    });
  });

  group('Stored values', () {
    test('refuses a NaN, which SQLite would store as NULL', () async {
      final db = await openWith('nan.db', ['CREATE TABLE measures (id INTEGER PRIMARY KEY, value REAL)']);

      await expectLater(
        db.runSql('INSERT INTO measures (value) VALUES (?)', [const Value.real(double.nan)]),
        throwsArgumentError,
      );
      expect(await countOf(db, 'measures'), 0);
      await db.dispose();
    });

    test('reads a whole number back from a NUMERIC column as a double', () async {
      final db = await openWith('numeric.db', ['CREATE TABLE prices (amount DECIMAL(10, 2))']);
      await db.runSql('INSERT INTO prices (amount) VALUES (?)', [const Value.real(3.0)]);

      final rows = await db.runRawQuery('SELECT amount FROM prices');

      expect(rows.single['amount']!.asDouble, 3.0, reason: 'SQLite keeps 3.0 in a NUMERIC column as the integer 3');
      await db.dispose();
    });

    test('refuses a time whose offset is not a whole number of minutes', () {
      const time = Time(hour: 1, minute: 2, utcOffset: Duration(seconds: 90));

      expect(() => Value.time(time), throwsArgumentError);
    });

    test('refuses a time whose offset is a day or more', () {
      const time = Time(hour: 1, minute: 2, utcOffset: Duration(hours: 100));

      expect(() => Value.time(time), throwsArgumentError);
    });
  });
}
