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
import 'dart:convert';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'schema/schema.dart';
import 'sort_order.dart';

part 'types/database_type.dart';
part 'types/native.dart';
part 'types/boolean.dart';
part 'types/temporal.dart';
part 'types/enum_value.dart';
part 'types/list.dart';
part 'types/uuid.dart';
part 'types/location.dart';
part 'types/interval.dart';
part 'types/range.dart';
part 'types/json.dart';
part 'types/row.dart';
part 'record.dart';
part 'column.dart';
part 'errors.dart';
part 'filter.dart';
part 'insert.dart';
part 'query.dart';
part 'update.dart';
part 'delete.dart';
part 'transaction.dart';
part 'batch.dart';
part 'field.dart';
part 'table.dart';
part 'session.dart';
part 'declared.dart';

/// A local SQLite database, opened once and reused — the same open, create,
/// migrate and close lifecycle every sqflite-backed store in pylon would
/// otherwise hand-roll for itself.
///
/// Unlike [LocalStorage] — a key-value cache with one fixed table it never
/// lets a caller see the shape of — this assumes nothing about what tables
/// exist or what a row looks like: a project (or another pylon primitive)
/// supplies its own schema through [onCreate] and [onUpgrade], then reads
/// and writes it through [insert], [query], [update], [delete], raw SQL and
/// [transaction], typed throughout on [DatabaseType] and [DatabaseRow] rather than
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
///     title: row.required('title').asString,
///     done: row.required('done').asBoolean,
///   );
///
///   @override
///   DatabaseRow toRow() => {'title': DatabaseType.varchar(title), 'done': DatabaseType.boolean(done)};
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
///   (q) => q.from('todos').where((w) => w.isEqualTo(key: 'done', value: DatabaseType.boolean(false))).map(Todo.fromRow),
/// );
/// await db.update<Todo>(
///   (u) => u
///       .table('todos')
///       .set(Todo(title: 'Ship it', done: true))
///       .where((w) => w.isEqualTo(key: 'id', value: DatabaseType.integer(id))),
/// );
/// await db.delete((d) => d.from('todos').where((w) => w.isEqualTo(key: 'done', value: DatabaseType.boolean(true))));
/// ```
///
/// Tables declared as [DatabaseTable] classes replace the strings, the
/// callbacks and the row maps above. [LocalDatabase.declared] creates and
/// migrates them, and each column is a typed [DatabaseField], so a filter
/// takes the Dart type of its own column:
///
/// ```dart
/// final db = LocalDatabase.declared(name: 'app.db', tables: [todos]);
///
/// final saved = await todos.on(db).insert(Todo(title: 'Ship it'));
/// final open = await todos.on(db).where(todos.done.isEqualTo(false)).orderBy([todos.title.asc()]).list();
/// await todos.on(db).where(todos.id.isEqualTo(saved.id!)).update([todos.done.to(true)]);
/// final total = await todos.on(db).count();
/// ```
///
/// A [DatabaseException] sqflite itself throws never escapes: every method
/// below throws the [DatabaseError] [DatabaseError.from] reads out
/// of it instead, so a caller matches a closed set of reasons rather than
/// sqflite's own message text. A call made before [open] or after [dispose]
/// throws a [StateError] instead, and a value SQLite cannot store, such as a
/// NaN, throws an [ArgumentError]: those are mistakes in the code, not
/// failures of the database.
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
class LocalDatabase extends DatabaseSession {
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
  final List<DatabaseTable<Object>>? _tables;
  final List<DeclaredTable> _declarations;
  final List<DatabaseMigration> _migrations;
  Database? _db;
  Future<void>? _opening;
  (DatabaseFactory, String)? _sharedKey;

  /// Opens the database file called [name], inside [factory]'s own
  /// databases directory, once [open] runs.
  ///
  /// Called in this order, each only when it has work to do:
  /// [onConfigure] first — before [version] is even looked at, the right
  /// place for a `PRAGMA` such as `journal_mode`; then exactly one of
  /// [onCreate] (the file did not exist yet), [onUpgrade] ([version] is
  /// higher than what the file already recorded) or [onDowngrade] ([version]
  /// is lower); finally [onOpen], once the file is fully ready.
  ///
  /// Every connection is opened with `PRAGMA foreign_keys = ON` before
  /// [onConfigure] runs, because SQLite ignores a declared `FOREIGN KEY` unless
  /// each connection asks for it. A migration that rebuilds a table needs the
  /// opposite, and [onConfigure] is the only place that can switch it off,
  /// since SQLite refuses the pragma inside a transaction.
  ///
  /// [readOnly] opens the file as it already is: it never looks at [version],
  /// so [onCreate], [onUpgrade] and [onDowngrade] never run, while
  /// [onConfigure] and [onOpen] still do. [singleInstance] (on by default,
  /// matching sqflite's own default) hands back the same [Database] for a path
  /// already open rather than a second connection to it, and the file stays open
  /// until every [LocalDatabase] sharing it has been disposed. [factory] defaults to sqflite's own
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
       _factory = factory ?? databaseFactory,
       _tables = null,
       _declarations = const [],
       _migrations = const [];

  /// Opens the database file called [name] with the schema declared by
  /// [tables], and creates and migrates that schema by itself, so that no
  /// `CREATE TABLE`, no version number and no `PRAGMA` is written by hand.
  ///
  /// When [open] runs, inside one transaction: every table that does not
  /// exist yet is created, and so is every column a declared table gained
  /// since the file was written, provided SQLite can add it, which means it is
  /// nullable or has a [DatabaseField.defaultsTo] and is neither a key nor
  /// unique. A change SQLite cannot make on its own, such as removing or
  /// renaming a column or filling a new column from another, is a [migrations]
  /// entry. Entry number `n`, counting from zero, upgrades a file from version
  /// `n + 1` to version `n + 2`, so the schema version is the length of
  /// [migrations] plus one and is stored in the file. Migrations run before
  /// the declared tables are brought up to date, and see the file as the older
  /// version left it. A fresh file runs none of them.
  ///
  /// A file written by a newer version of the code is refused with a
  /// [DatabaseSchemaTooNewError] instead of being read wrongly.
  ///
  /// Foreign keys are enforced, as on every [LocalDatabase], and on a writable
  /// file the journal is in write-ahead mode, which SQLite leaves off unless
  /// asked.
  ///
  /// [declarations] adds tables written with [TableBuilder] that no
  /// [DatabaseTable] describes, such as one reached only through [execute] and
  /// [rawQuery]. [readOnly] opens the file as it is, with no schema work.
  /// [singleInstance] and [factory] are the ones the default constructor takes.
  LocalDatabase.declared({
    required String name,
    required List<DatabaseTable<Object>> tables,
    List<DeclaredTable> declarations = const [],
    List<DatabaseMigration> migrations = const [],
    bool readOnly = false,
    bool singleInstance = true,
    DatabaseFactory? factory,
  }) : _name = name,
       _version = 1,
       _onConfigure = _configureDeclared(readOnly),
       _onCreate = null,
       _onUpgrade = null,
       _onDowngrade = null,
       _onOpen = null,
       _readOnly = readOnly,
       _singleInstance = singleInstance,
       _factory = factory ?? databaseFactory,
       _tables = tables,
       _declarations = declarations,
       _migrations = migrations;

  /// Whether [open] has run and [dispose] has not undone it.
  bool get isOpen => _db?.isOpen ?? false;

  /// Opens the database file, running whichever of [onConfigure], [onCreate],
  /// [onUpgrade], [onDowngrade] and [onOpen] has work to do, and makes this
  /// instance usable.
  ///
  /// Calling it twice is harmless: the second call does nothing, and a second
  /// call made while the first is still running waits for it instead of opening
  /// another connection.
  ///
  /// Throws a [DatabaseOpenFailedError] when SQLite cannot open the file and
  /// gives no more precise reason, such as a read only open of a file that does
  /// not exist.
  Future<void> open() {
    if (_db != null) return Future<void>.value();
    return _opening ??= _openFile().whenComplete(() => _opening = null);
  }

  Future<void> _openFile() async {
    try {
      final directory = await _factory.getDatabasesPath();
      final path = p.join(directory, _name);
      final db = await _factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: _readOnly || _tables != null ? null : _version,
          onConfigure: _configure,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
          onDowngrade: _onDowngrade,
          onOpen: _onOpen,
          readOnly: _readOnly,
          singleInstance: _singleInstance,
        ),
      );
      if (_singleInstance) {
        _sharedKey = (_factory, path);
        _sharedInstances.update((_factory, path), (count) => count + 1, ifAbsent: () => 1);
      }
      if (_tables != null && !_readOnly) {
        try {
          await _synchronizeSchema(this, db);
        } catch (_) {
          await _close(db);
          rethrow;
        }
      }
      _db = db;
    } on DatabaseException catch (error) {
      final reason = DatabaseError.from(error);
      throw reason is DatabaseUnknownError ? DatabaseOpenFailedError(reason.message) : reason;
    }
  }

  Future<void> _configure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    await _onConfigure?.call(db);
  }

  /// Runs [sql] directly, for anything [insert], [query], [update] and
  /// [delete] do not cover — a `CREATE TABLE`, a `CREATE INDEX`, a schema
  /// change inside [onUpgrade].
  Future<void> execute(String sql, [List<DatabaseType>? arguments]) =>
      _guarded(() => _executor().execute(sql, _toNativeArgs(arguments)));

  /// Inserts one row, composed by [build] from an empty [DatabaseInsert] —
  /// [build] must return a fully composed [DatabaseInsertValues], the same way
  /// a raw `INSERT` needs an `INTO` and a `VALUES` before it means anything
  /// — answering the row id sqflite assigned.
  Future<int> insert<T extends DatabaseRecord>(DatabaseInsertValues<T> Function(DatabaseInsert<T> insert) build) =>
      _guarded(() {
        final spec = build(DatabaseInsert<T>._());
        return _executor().rawInsert(spec._sql, spec._arguments);
      });

  /// Reads rows, filtered, ordered, paged and decoded exactly as [build]
  /// composes it from an empty [DatabaseQuery] — [build] must return a
  /// [DatabaseQueryFrom], the same way a raw `SELECT` needs a `FROM` before it
  /// means anything.
  Future<List<T>> query<T extends Object>(DatabaseQueryFrom<T> Function(DatabaseQuery<T> query) build) =>
      _guarded(() async {
        final spec = build(DatabaseQuery<T>._());
        final rows = await _executor().query(
          spec._table,
          distinct: spec._distinct,
          columns: spec._columns,
          where: spec._where,
          whereArgs: _toNativeArgs(spec._arguments),
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
  Future<List<DatabaseRow>> rawQuery(String sql, [List<DatabaseType>? arguments]) => _guarded(() async {
    final rows = await _executor().rawQuery(sql, _toNativeArgs(arguments));
    return rows.map(_fromNativeRow).toList();
  });

  /// Writes one row over every row matched, composed by [build] from an
  /// empty [DatabaseUpdate] — [build] must return a [DatabaseUpdateSet], the same
  /// way a raw `UPDATE table` needs a `SET` before it means anything —
  /// answering how many rows changed.
  Future<int> update<T extends DatabaseRecord>(DatabaseUpdateSet<T> Function(DatabaseUpdate<T> update) build) =>
      _guarded(() {
        final spec = build(DatabaseUpdate<T>._());
        return _executor().update(
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
    return _executor().delete(spec._table, where: spec._where, whereArgs: _toNativeArgs(spec._whereArgs));
  });

  /// Runs [action] as one transaction: every write inside it commits
  /// together, or none of them do if [action] throws.
  ///
  /// Everything [action] asks of this [LocalDatabase], and of a [batch] made
  /// from it, joins the transaction, the same as if it had gone through the
  /// [DatabaseTransaction] it is given, because sqflite would otherwise wait
  /// forever for a transaction that is itself waiting for the database. That
  /// holds for the code [action] awaits, at any depth. A [transaction] called
  /// inside [action] joins the outer one rather than starting another, so its
  /// writes are kept or undone with the outer transaction, not on their own.
  Future<T> transaction<T>(Future<T> Function(DatabaseTransaction txn) action) => _guarded(() {
    final db = _requireOpen();
    final joined = _joinedTransaction(db);
    if (joined != null) return action(DatabaseTransaction._(joined, this));
    return db.transaction((txn) => _inTransaction(db, txn, () => action(DatabaseTransaction._(txn, this))));
  });

  /// Starts a batch: a sequence of writes queued here, none of which touch
  /// the database until [DatabaseBatch.commit] or [DatabaseBatch.apply] runs them.
  ///
  /// Prefer this over calling [insert] (or [update], or [delete]) once per
  /// row in a loop: each of those otherwise opens and commits its own
  /// implicit transaction, which for anything beyond a handful of rows is
  /// the difference between finishing instantly and taking seconds, since
  /// every commit costs its own fsync.
  DatabaseBatch batch() => DatabaseBatch._(_executor());

  /// Whether [table] exists in this database.
  Future<bool> tableExists(String table) => _guarded(() async {
    final rows = await rawQuery("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", [
      DatabaseType.varchar(table),
    ]);
    return rows.isNotEmpty;
  });

  /// The name of every table this database declares, excluding SQLite's own
  /// internal `sqlite_` tables.
  Future<List<String>> tableNames() => query<String>(
    (q) => q
        .from('sqlite_master')
        .select(const ['name'])
        .where((w) => w.raw("type = 'table' AND name NOT LIKE 'sqlite\\_%' ESCAPE '\\'"))
        .map((row) => row['name']!.asString),
  );

  /// Every column [table] declares, in declaration order, straight out of
  /// `PRAGMA table_xinfo`, which unlike `table_info` also lists the generated
  /// columns.
  ///
  /// Falls back to `table_info` on a SQLite older than 3.26, which does not
  /// know `table_xinfo` and answers no row for it, and which has no
  /// generated column to leave out.
  ///
  /// Answers an empty list for a table that does not exist; [tableExists]
  /// tells that answer apart from a table that has columns.
  Future<List<DatabaseColumn>> columns(String table) => _guarded(() async {
    final quoted = _quotedIdentifier(table);
    final extended = await rawQuery('PRAGMA table_xinfo($quoted)');
    final rows = extended.isNotEmpty ? extended : await rawQuery('PRAGMA table_info($quoted)');
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
  /// twice. Waits for an [open] still running, so that it never leaves the
  /// file open behind it. When another [LocalDatabase] with `singleInstance`
  /// holds the same file open, the file stays open until the last of them is
  /// disposed.
  Future<void> dispose() async {
    final opening = _opening;
    if (opening != null) await opening.then<void>((_) {}, onError: (Object _) {});
    final db = _db;
    if (db == null) return;
    _db = null;
    await _close(db);
  }

  Future<void> _close(Database db) async {
    if (_leavesOthersOpen()) return;
    await _guarded(db.close);
  }

  bool _leavesOthersOpen() {
    final key = _sharedKey;
    if (key == null) return false;
    _sharedKey = null;
    final remaining = _sharedInstances[key]! - 1;
    if (remaining > 0) {
      _sharedInstances[key] = remaining;
      return true;
    }
    _sharedInstances.remove(key);
    return false;
  }

  Database _requireOpen() {
    final db = _db;
    if (db == null) {
      throw StateError('Database is not open. Call open() first.');
    }
    return db;
  }

  @override
  DatabaseExecutor _executor() {
    final db = _requireOpen();
    return _joinedTransaction(db) ?? db;
  }

  @override
  LocalDatabase get _database => this;

  @override
  Future<T> _atomically<T>(Future<T> Function(DatabaseSession session) action) => transaction(action);

  void _requireDeclared(DatabaseTable<Object> table) {
    final tables = _tables;
    if (tables != null && !tables.any((declared) => declared.tableName == table.tableName)) {
      throw StateError('${table.tableName} is not among the tables this LocalDatabase was declared with.');
    }
  }
}

final Map<(DatabaseFactory, String), int> _sharedInstances = {};

final Object _transactionZoneKey = Object();

final class _ActiveTransaction {
  const _ActiveTransaction(this.database, this.transaction);

  final Database database;
  final Transaction transaction;
}

Transaction? _joinedTransaction(Database database) {
  final active = Zone.current[_transactionZoneKey];
  return active is _ActiveTransaction && identical(active.database, database) ? active.transaction : null;
}

Future<T> _inTransaction<T>(Database database, Transaction transaction, Future<T> Function() action) =>
    Zone.current.fork(zoneValues: {_transactionZoneKey: _ActiveTransaction(database, transaction)}).run(action);

String _quotedIdentifier(String identifier) => '"${identifier.replaceAll('"', '""')}"';
