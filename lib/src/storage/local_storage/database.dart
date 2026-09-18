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

import 'dart:async';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

part 'sql_value.dart';
part 'record.dart';
part 'column.dart';
part 'errors.dart';
part 'insert.dart';
part 'query.dart';
part 'update.dart';
part 'delete.dart';
part 'transaction.dart';
part 'batch.dart';

/// A local SQLite database, opened once and reused — the same open, create,
/// migrate and close lifecycle every sqflite-backed store in pylon would
/// otherwise hand-roll for itself.
///
/// Unlike [LocalStorage] — a key-value cache with one fixed table it never
/// lets a caller see the shape of — this assumes nothing about what tables
/// exist or what a row looks like: a project (or another pylon primitive)
/// supplies its own schema through [onCreate] and [onUpgrade], then reads
/// and writes it through [insert], [query], [update], [delete], raw SQL and
/// [transaction], typed throughout on [SqlValue] and [DatabaseRow] rather than
/// `Object?`. This adds only the lifecycle sqflite leaves to the caller; it
/// never reinterprets a column, a table name or a query as meaning
/// something.
///
/// ```dart
/// class Todo implements DatabaseRecord {
///   Todo({required this.title, required this.done});
///   final String title;
///   final bool done;
///
///   static Todo fromRow(DatabaseRow row) => Todo(
///     title: (row['title'] as SqlText).value,
///     done: (row['done'] as SqlInteger).value != 0,
///   );
///
///   @override
///   DatabaseRow toRow() => {'title': SqlValue.text(title), 'done': SqlValue.boolean(done)};
/// }
///
/// final db = LocalDatabase(
///   name: 'app.db',
///   version: 1,
///   onCreate: (db, version) => db.execute(
///     'CREATE TABLE todos ('
///     'id INTEGER PRIMARY KEY AUTOINCREMENT, '
///     'title TEXT NOT NULL, '
///     'done INTEGER NOT NULL DEFAULT 0'
///     ')',
///   ),
/// );
/// await db.open();
///
/// final id = await db.insert<Todo>((i) => i.into('todos').values(Todo(title: 'Ship it', done: false)));
/// final open = await db.query<Todo>(
///   (q) => q.from('todos').where('done = ?', [SqlValue.boolean(false)]).map(Todo.fromRow),
/// );
/// await db.update<Todo>(
///   (u) => u.table('todos').set(Todo(title: 'Ship it', done: true)).where('id = ?', [SqlValue.integer(id)]),
/// );
/// await db.delete((d) => d.from('todos').where('done = ?', [SqlValue.boolean(true)]));
/// ```
///
/// A [DatabaseException] sqflite itself throws never escapes: every method
/// below throws the [DatabaseError] [DatabaseError.from] reads out
/// of it instead, so a caller matches a closed set of reasons rather than
/// sqflite's own message text.
///
/// [SqfliteSyncStore] and [SqfliteMutationStore] each open their own
/// database and hand-roll this exact lifecycle today; moving them onto this
/// instead is a later, separate change, not something this file does on its
/// own.
///
/// Deliberately absent: encryption (swap [factory] for one such as
/// `sqflite_sqlcipher`'s own instead), backup/restore (checkpoint through
/// [checkpoint] first, then copy the file — and its `-wal`/`-shm` siblings —
/// with `dart:io` directly), `VACUUM` (run `execute('VACUUM')` directly; it
/// is rare enough, and expensive enough, to not deserve its own method), and
/// reactive/streamed query results (a project builds that on top of
/// [insert]/[update]/[delete] already telling it a write happened, rather
/// than pylon guessing which table a raw [execute] touched).
class LocalDatabase {
  final String _name;
  final int _version;
  final OnDatabaseConfigureFn? _onConfigure;
  final OnDatabaseCreateFn? _onCreate;
  final OnDatabaseVersionChangeFn? _onUpgrade;
  final OnDatabaseVersionChangeFn? _onDowngrade;
  final OnDatabaseOpenFn? _onOpen;
  final bool _readOnly;
  final bool _singleInstance;
  final DatabaseFactory _factory;
  Database? _db;

  /// Opens the database file called [name], inside [factory]'s own
  /// databases directory, once [open] runs.
  ///
  /// Called in this order, each only when it has work to do:
  /// [onConfigure] first — before [version] is even looked at, the right
  /// place for a `PRAGMA` such as `foreign_keys` or `journal_mode`, since
  /// pylon sets none on a project's behalf; then exactly one of [onCreate]
  /// (the file did not exist yet), [onUpgrade] ([version] is higher than
  /// what the file already recorded) or [onDowngrade] ([version] is lower);
  /// finally [onOpen], once the file is fully ready.
  ///
  /// [readOnly] opens the file as it already is and skips every callback
  /// above. [singleInstance] (on by default, matching sqflite's own default)
  /// hands back the same [Database] for a path already open rather than a
  /// second connection to it. [factory] defaults to sqflite's own
  /// [databaseFactory]; give it `databaseFactoryFfi` in a test, or another
  /// implementation's own factory — `sqflite_sqlcipher`'s, say — to encrypt
  /// the file without this class knowing that happened.
  LocalDatabase({
    required String name,
    int version = 1,
    OnDatabaseConfigureFn? onConfigure,
    OnDatabaseCreateFn? onCreate,
    OnDatabaseVersionChangeFn? onUpgrade,
    OnDatabaseVersionChangeFn? onDowngrade,
    OnDatabaseOpenFn? onOpen,
    bool readOnly = false,
    bool singleInstance = true,
    DatabaseFactory? factory,
  }) : _name = name,
       _version = version,
       _onConfigure = onConfigure,
       _onCreate = onCreate,
       _onUpgrade = onUpgrade,
       _onDowngrade = onDowngrade,
       _onOpen = onOpen,
       _readOnly = readOnly,
       _singleInstance = singleInstance,
       _factory = factory ?? databaseFactory;

  /// Whether [open] has run and [dispose] has not undone it.
  bool get isOpen => _db != null;

  /// Opens the database file, running whichever of [onConfigure], [onCreate],
  /// [onUpgrade], [onDowngrade] and [onOpen] has work to do, and makes this
  /// instance usable.
  ///
  /// Calling it twice is harmless: the second call does nothing.
  Future<void> open() => _guarded(() async {
    if (_db != null) return;
    final directory = await _factory.getDatabasesPath();
    _db = await _factory.openDatabase(
      p.join(directory, _name),
      options: OpenDatabaseOptions(
        version: _version,
        onConfigure: _onConfigure,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onDowngrade: _onDowngrade,
        onOpen: _onOpen,
        readOnly: _readOnly,
        singleInstance: _singleInstance,
      ),
    );
  });

  /// Runs [sql] directly, for anything [insert], [query], [update] and
  /// [delete] do not cover — a `CREATE TABLE`, a `CREATE INDEX`, a schema
  /// change inside [onUpgrade].
  Future<void> execute(String sql, [List<SqlValue>? arguments]) =>
      _guarded(() => _requireOpen().execute(sql, _toNativeArgs(arguments)));

  /// Inserts one row, composed by [build] from an empty [DatabaseInsert] —
  /// [build] must return a fully composed [DatabaseInsertValues], the same way
  /// a raw `INSERT` needs an `INTO` and a `VALUES` before it means anything
  /// — answering the row id sqflite assigned.
  Future<int> insert<T extends DatabaseRecord>(DatabaseInsertValues<T> Function(DatabaseInsert<T> insert) build) =>
      _guarded(() {
        final spec = build(DatabaseInsert<T>._());
        return _requireOpen().insert(
          spec._table,
          _toNativeRow(spec._data.toRow()),
          conflictAlgorithm: spec._conflict,
        );
      });

  /// Reads rows, filtered, ordered, paged and decoded exactly as [build]
  /// composes it from an empty [DatabaseQuery] — [build] must return a
  /// [DatabaseQueryFrom], the same way a raw `SELECT` needs a `FROM` before it
  /// means anything.
  Future<List<T>> query<T extends Object>(DatabaseQueryFrom<T> Function(DatabaseQuery<T> query) build) =>
      _guarded(() async {
        final spec = build(DatabaseQuery<T>._());
        final rows = await _requireOpen().query(
          spec._table,
          distinct: spec._distinct,
          columns: spec._columns,
          where: spec._where,
          whereArgs: _toNativeArgs(spec._whereArgs),
          groupBy: spec._groupBy,
          having: spec._having,
          orderBy: spec._orderBy,
          limit: spec._limit,
          offset: spec._offset,
        );
        final fromRow = spec._requiredFromRow;
        return rows.map((row) => fromRow(_fromNativeRow(row))).toList();
      });

  /// Runs [sql] directly and answers the rows it selected, for a query
  /// [query] cannot express — a join, an aggregate, anything past one
  /// table's own `WHERE`.
  Future<List<DatabaseRow>> rawQuery(String sql, [List<SqlValue>? arguments]) => _guarded(() async {
    final rows = await _requireOpen().rawQuery(sql, _toNativeArgs(arguments));
    return rows.map(_fromNativeRow).toList();
  });

  /// Writes one row over every row matched, composed by [build] from an
  /// empty [DatabaseUpdate] — [build] must return a [DatabaseUpdateSet], the same
  /// way a raw `UPDATE table` needs a `SET` before it means anything —
  /// answering how many rows changed.
  Future<int> update<T extends DatabaseRecord>(DatabaseUpdateSet<T> Function(DatabaseUpdate<T> update) build) => _guarded(() {
    final spec = build(DatabaseUpdate<T>._());
    return _requireOpen().update(
      spec._table,
      _toNativeRow(spec._data.toRow()),
      where: spec._where,
      whereArgs: _toNativeArgs(spec._whereArgs),
      conflictAlgorithm: spec._conflict,
    );
  });

  /// Removes every row matched, composed by [build] from an empty
  /// [DatabaseDelete] — [build] must return a [DatabaseDeleteFrom], the same way
  /// a raw `DELETE` needs a `FROM` before it means anything — answering how
  /// many rows were removed.
  Future<int> delete(DatabaseDeleteFrom Function(DatabaseDelete delete) build) => _guarded(() {
    final spec = build(const DatabaseDelete._());
    return _requireOpen().delete(spec._table, where: spec._where, whereArgs: _toNativeArgs(spec._whereArgs));
  });

  /// Runs [action] as one transaction: every write inside it commits
  /// together, or none of them do if [action] throws.
  ///
  /// [action] never reaches for this [LocalDatabase] itself — only the
  /// [DatabaseTransaction] it is given — since sqflite deadlocks a transaction
  /// that touches the database it is running against directly instead of
  /// through the transaction object.
  Future<T> transaction<T>(Future<T> Function(DatabaseTransaction txn) action) =>
      _guarded(() => _requireOpen().transaction((txn) => action(DatabaseTransaction._(txn))));

  /// Starts a batch: a sequence of writes queued here, none of which touch
  /// the database until [DatabaseBatch.commit] or [DatabaseBatch.apply] runs them.
  ///
  /// Prefer this over calling [insert] (or [update], or [delete]) once per
  /// row in a loop: each of those otherwise opens and commits its own
  /// implicit transaction, which for anything beyond a handful of rows is
  /// the difference between finishing instantly and taking seconds, since
  /// every commit costs its own fsync.
  DatabaseBatch batch() => DatabaseBatch._(_requireOpen().batch());

  /// Whether [table] exists in this database.
  Future<bool> tableExists(String table) => _guarded(() async {
    final rows = await rawQuery("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", [
      SqlValue.text(table),
    ]);
    return rows.isNotEmpty;
  });

  /// The name of every table this database declares, excluding SQLite's own
  /// internal `sqlite_` tables.
  Future<List<String>> tableNames() => query<String>(
    (q) => q
        .from('sqlite_master')
        .select(const ['name'])
        .where("type = 'table' AND name NOT LIKE 'sqlite\\_%' ESCAPE '\\'")
        .map((row) => (row['name'] as SqlText).value),
  );

  /// Every column [table] declares, in declaration order, straight out of
  /// `PRAGMA table_info`.
  Future<List<DatabaseColumn>> columns(String table) => _guarded(() async {
    final rows = await rawQuery('PRAGMA table_info(${_quotedIdentifier(table)})');
    return rows.map(DatabaseColumn._fromRow).toList();
  });

  /// Writes every change still sitting in the write-ahead log back into the
  /// main database file, and truncates the log.
  ///
  /// Run this before copying the database file for a backup: with
  /// `journal_mode = WAL`, some already-committed data lives only in a
  /// separate `-wal` file until a checkpoint like this one folds it back in.
  Future<void> checkpoint() => execute('PRAGMA wal_checkpoint(TRUNCATE)');

  /// Closes the database.
  ///
  /// Safe to call on an instance that was never opened, and safe to call
  /// twice.
  Future<void> dispose() async {
    await _db?.close();
    _db = null;
  }

  Database _requireOpen() {
    final db = _db;
    if (db == null) {
      throw StateError('Database is not open. Call open() first.');
    }
    return db;
  }
}

String _quotedIdentifier(String identifier) => '"${identifier.replaceAll('"', '""')}"';
