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
import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:get_it/get_it.dart' show GetIt;
import 'package:injectable/injectable.dart' show FactoryMethod, Singleton, disposeMethod;
import 'package:meta/meta.dart' show internal, visibleForTesting;
import 'package:package_info_plus/package_info_plus.dart' show PackageInfo;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher show databaseFactory;
import 'package:sqflite_sqlcipher/sqlite_api.dart' show SqlCipherOpenDatabaseOptions;
import 'package:uuid/uuid.dart';

import '../../../../../credential/credential.dart' show CredentialStatus;
import '../../../../../credential/manager.dart' show CredentialManager;
import '../../../../../storage/secure_storage.dart' show Fingerprint, SecureStorage;
import 'schema/schema.dart';
import 'query/sort_order.dart';

part 'types/value.dart';
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
part 'query/record.dart';
part 'schema/column_info.dart';
part 'schema/drift.dart';
part 'errors.dart';
part 'query/filter.dart';
part 'query/insert.dart';
part 'query/query.dart';
part 'query/update.dart';
part 'query/delete.dart';
part 'transaction/transaction.dart';
part 'transaction/batch.dart';
part 'table/field.dart';
part 'table/table.dart';
part 'table/tenant.dart';
part 'table/reactive.dart';
part 'table/session.dart';
part 'table/declared.dart';
part 'lifecycle/health.dart';

/// The one SQLite database of the app, shared by everything that stores rows.
///
/// It is a file named after the app in snake case (`my_app.db`), opened once when `configureSdk` runs and closed by
/// `GetIt.reset`. A project neither creates it nor opens it: it calls the static methods below, or reaches it through
/// the layer above, with [TypedTable] classes declared in a `Database`.
///
/// ```dart
/// final id = await LocalDatabase.insert<Todo>((i) => i.into('todos').values(todo));
/// final todos = await LocalDatabase.query<Todo>((q) => q.from('todos').map(Todo.fromRow));
/// ```
///
/// The static methods reach the whole database, every tenant included, and present the app's own [Fingerprint]
/// (`SecureStorage.fingerprint`) on the caller's behalf.
///
/// The file is created empty on a first launch and used as it is when it reads fine. When opening it fails, or when
/// SQLite's integrity check finds it damaged, it is deleted and created again and its content is lost. The exception
/// is an app that turns encryption on over a database in clear: startup then throws a [StateError] and the file is
/// left alone.
///
/// It carries no schema of its own. Whoever uses it creates the tables it needs with `CREATE TABLE IF NOT EXISTS`, or
/// declares [TypedTable] classes, since the file may be a fresh one on any launch.
///
/// A [DatabaseException] thrown by sqflite never escapes: every method throws the [StoreError] that [StoreError.from]
/// reads out of it, so a caller matches a closed set of reasons rather than sqflite's message text. A call made
/// before [open] or after [dispose] throws a [StateError], and a value SQLite cannot store, such as a NaN, throws an
/// [ArgumentError]. Those are mistakes in the code, not failures of the database.
///
/// Every write made through this class tells the streams watching the tables it touched (see [Rows.watch]): a typed
/// write, [insert], [update], [delete], a [batch] and a [transaction], the last one only once it has committed and
/// not at all when it rolls back. A raw [execute] or a [batch] cannot say which table it changed, so it tells every
/// watcher, and each one reads again and stays quiet when nothing it watches differs.
///
/// A test builds its own with [LocalDatabase.forTesting] or [LocalDatabase.declaredForTesting], which take a name, a
/// version, the SQLite callbacks and a [DatabaseFactory], and reaches it through the instance methods (`runInsert`,
/// `runQuery` and their siblings). Those carry other names than the static ones, since Dart does not allow a static
/// and an instance member of the same name.
///
/// Deliberately absent: backup and restore, for which a caller runs [checkpoint], then copies the file and its `-wal`
/// and `-shm` siblings with `dart:io`, and `VACUUM`, which `execute('VACUUM')` runs and which is too rare and too
/// expensive to deserve its own method.
@Singleton()
class LocalDatabase extends Connection {
  /// The file name of this database, inside [_factory]'s databases directory.
  final String _name;

  /// The schema version [_onCreate], [_onUpgrade] and [_onDowngrade] are decided against.
  ///
  /// Not used on a read only or a declared database, which never look at it.
  final int _version;

  /// Backs the `onConfigure` callback of [LocalDatabase.forTesting].
  final OnDatabaseConfigureFn? _onConfigure;

  /// Backs the `onCreate` callback of [LocalDatabase.forTesting].
  final OnDatabaseCreateFn? _onCreate;

  /// Backs the `onUpgrade` callback of [LocalDatabase.forTesting].
  final OnDatabaseVersionChangeFn? _onUpgrade;

  /// Backs the `onDowngrade` callback of [LocalDatabase.forTesting].
  final OnDatabaseVersionChangeFn? _onDowngrade;

  /// Backs the `onOpen` callback of [LocalDatabase.forTesting].
  final OnDatabaseOpenFn? _onOpen;

  /// Whether the file is opened as it is, with no schema work.
  final bool _readOnly;

  /// Whether a second [LocalDatabase] on the same file shares this connection instead of opening its own.
  final bool _singleInstance;

  /// The factory the file is opened, deleted and located with.
  final DatabaseFactory _factory;

  /// The tables declared on this database, or `null` when it was declared none, in which case it accepts every table.
  List<TypedTable<Object>>? _tables;

  /// The end of the last [declareTables] call, which the next call waits for.
  ///
  /// It completes normally even when that call failed.
  Future<void> _declaring = Future<void>.value();

  /// The tables written with [TableBuilder] that no [TypedTable] describes.
  final List<DeclaredTable> _declarations;

  /// The schema upgrades of a declared database, see [LocalDatabase.declaredForTesting].
  final List<Migration> _migrations;

  /// The fingerprint a whole-database call must present, or `null` when that mechanism is closed on this database.
  final Fingerprint? _fingerprint;

  /// Backs [encrypted].
  final bool _encrypted;

  /// The open connection, or `null` before [open] and after [dispose].
  Database? _db;

  /// The [open] in progress, which a second call waits for instead of opening another connection.
  Future<void>? _opening;

  /// The tables each write touched, or `null` for every table, which [Rows.watch] follows.
  final StreamController<Set<String>?> _writes = StreamController<Set<String>?>.broadcast();

  /// The file this instance is counted under in [_sharedInstances], or `null` when it is not counted.
  (DatabaseFactory, String)? _sharedKey;

  /// Creates a database on the file called [name], which [open] then opens inside [factory]'s databases directory.
  ///
  /// The callbacks run in this order, each only when it has work to do. [onConfigure] comes first, before [version] is
  /// looked at, which makes it the place for a `PRAGMA` such as `journal_mode`. Then exactly one of [onCreate] (the
  /// file did not exist yet), [onUpgrade] ([version] is higher than the file's) or [onDowngrade] ([version] is
  /// lower). [onOpen] comes last, once the file is ready.
  ///
  /// Every connection is opened with `PRAGMA foreign_keys = ON` before [onConfigure] runs, because SQLite ignores a
  /// declared `FOREIGN KEY` unless each connection asks for it. A migration that rebuilds a table needs the opposite,
  /// and [onConfigure] is the only place that can switch it off, since SQLite refuses that pragma inside a
  /// transaction.
  ///
  /// With [readOnly] the file is opened as it is: [version] is never looked at, so [onCreate], [onUpgrade] and
  /// [onDowngrade] never run, while [onConfigure] and [onOpen] still do. With [singleInstance], which is on by
  /// default as it is in sqflite, a path that is already open hands back the same connection instead of opening a
  /// second one, and the file stays open until every [LocalDatabase] sharing it has been disposed. [factory] defaults
  /// to sqflite's [databaseFactory]; a test gives it `databaseFactoryFfi`.
  ///
  /// [fingerprint] opens the whole-database mechanism ([wholeDatabase], [TypedTable.onWholeDatabase]): without one,
  /// that mechanism is closed on this database, and with one, a call must present the same fingerprint. With
  /// [encrypt] the file is also encrypted with a key derived from [fingerprint], so a copy of it cannot be read
  /// without it. That needs the SQLCipher factory of `sqflite_sqlcipher` as [factory]: on any other SQLite, [open]
  /// throws an [EncryptionUnavailableError] instead of writing the file in clear.
  ///
  /// Throws an [ArgumentError] if [encrypt] is set without a [fingerprint].
  @visibleForTesting
  LocalDatabase.forTesting({
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
    Fingerprint? fingerprint,
    bool encrypt = false,
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
       _migrations = const [],
       _fingerprint = fingerprint,
       _encrypted = encrypt {
    _requireFingerprintToEncrypt(encrypt, fingerprint);
  }

  /// Creates a database on the file called [name] whose schema is the one [tables] declare, created and migrated
  /// without a `CREATE TABLE`, a version number or a `PRAGMA` written by hand.
  ///
  /// When [open] runs, one transaction creates every table that does not exist yet and every column a declared table
  /// gained since the file was written. SQLite can add a column only if it is nullable or has a [Field.defaultsTo],
  /// and is neither a key nor unique. Any other change, such as removing or renaming a column or filling a new column
  /// from another, is a [migrations] entry. Entry number `n`, counting from zero, upgrades a file from version `n + 1`
  /// to version `n + 2`, so the schema version is the length of [migrations] plus one, and it is stored in the file.
  /// Migrations run before the declared tables are brought up to date and see the file as the older version left it.
  /// A fresh file runs none of them.
  ///
  /// A file written by a newer version of the code is refused with a [SchemaTooNewError] instead of being read
  /// wrongly.
  ///
  /// Foreign keys are enforced, as on every [LocalDatabase], and a writable file uses SQLite's write-ahead journal.
  ///
  /// [declarations] adds tables written with [TableBuilder] that no [TypedTable] describes, such as one reached only
  /// through [execute] and [rawQuery]. [readOnly] opens the file as it is, with no schema work. [singleInstance],
  /// [factory], [fingerprint] and [encrypt] are the ones [LocalDatabase.forTesting] takes.
  ///
  /// Throws an [ArgumentError] if [encrypt] is set without a [fingerprint].
  @visibleForTesting
  LocalDatabase.declaredForTesting({
    required String name,
    required List<TypedTable<Object>> tables,
    List<DeclaredTable> declarations = const [],
    List<Migration> migrations = const [],
    bool readOnly = false,
    bool singleInstance = true,
    DatabaseFactory? factory,
    Fingerprint? fingerprint,
    bool encrypt = false,
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
       _migrations = migrations,
       _fingerprint = fingerprint,
       _encrypted = encrypt {
    _requireFingerprintToEncrypt(encrypt, fingerprint);
  }

  static void _requireFingerprintToEncrypt(bool encrypt, Fingerprint? fingerprint) {
    if (encrypt && fingerprint == null) {
      throw ArgumentError.value(encrypt, 'encrypt', 'needs a fingerprint to derive the key from');
    }
  }

  LocalDatabase._app({
    required String name,
    required DatabaseFactory factory,
    required Fingerprint? fingerprint,
    required bool encrypt,
  }) : this.forTesting(name: name, factory: factory, fingerprint: fingerprint, encrypt: encrypt);

  /// Whether the app database is encrypted, by a key derived from the app's own [Fingerprint], so that a copy of the
  /// file cannot be read without it.
  ///
  /// `false` when [encryption] is [EncryptionPolicy.whenAvailable] and the platform has no SQLCipher: the data is then
  /// in clear, and this is how a project finds out.
  static bool get isEncrypted => instance.encrypted;

  /// The [EncryptionPolicy] the app database is opened with.
  ///
  /// Set it before `configureSdk` runs, since that is when the database is opened.
  static EncryptionPolicy encryption = EncryptionPolicy.whenAvailable;

  /// Opens the app database for `configureSdk`, repairing the file if it is damaged.
  ///
  /// Called by `configureSdk`, never by a project. [secureStorage] is only there so that the secure storage, which
  /// holds the fingerprint, is built first.
  ///
  /// Throws a [StateError] if the file is a database in clear and the app database is to be encrypted. The file is
  /// left alone, since deleting it would lose data that was never encrypted.
  @internal
  @FactoryMethod(preResolve: true)
  static Future<LocalDatabase> initialize(SecureStorage secureStorage) =>
      _openAppDatabase(fingerprint: SecureStorage.fingerprint, encryption: encryption);

  /// Opens the app database the way [initialize] does, for a test that points it at [factory]'s directory.
  ///
  /// [appName] stands for the name the platform would give the app. The result is not registered anywhere: the test
  /// owns it and disposes it.
  @visibleForTesting
  static Future<LocalDatabase> openForTesting({
    String? appName,
    DatabaseFactory? factory,
    Fingerprint? fingerprint,
    EncryptionPolicy encryption = EncryptionPolicy.whenAvailable,
  }) => _openAppDatabase(appName: appName, factory: factory, fingerprint: fingerprint, encryption: encryption);

  /// The app database, for what is inside the package: the typed tables and the tenant mechanism, which reach only
  /// what they are meant to.
  ///
  /// Not for a project. Reading the database as a whole is what the static calls below are for.
  @internal
  static LocalDatabase get instance => GetIt.instance<LocalDatabase>();

  /// Declares [tables] on the app database and creates what they declare, see [declareTables].
  @internal
  static Future<void> declare(List<TypedTable<Object>> tables) => instance.declareTables(tables);

  /// A value that changes each time `configureSdk` registers a new [LocalDatabase].
  ///
  /// Something that prepared the database once, a table it created for instance, compares it to tell that what it
  /// prepared is no longer the database in use.
  @internal
  static Object get generation => instance;

  /// The app database with the whole-database mechanism open, which the static methods run on.
  static LocalDatabase get _whole {
    final db = instance;
    db.wholeDatabase(SecureStorage.fingerprint);
    return db;
  }

  /// Same as [runSql], on the whole app database.
  static Future<void> execute(String sql, [List<Value>? arguments]) => _whole.runSql(sql, arguments);

  /// Same as [runInsert], on the whole app database.
  static Future<int> insert<T extends Storable>(InsertValues<T> Function(Insert<T> insert) build) =>
      _whole.runInsert<T>(build);

  /// Same as [runQuery], on the whole app database.
  static Future<List<T>> query<T extends Object>(QueryFrom<T> Function(Select<T> query) build) =>
      _whole.runQuery<T>(build);

  /// Same as [runRawQuery], on the whole app database.
  static Future<List<RawRow>> rawQuery(String sql, [List<Value>? arguments]) => _whole.runRawQuery(sql, arguments);

  /// Same as [runUpdate], on the whole app database.
  static Future<int> update<T extends Storable>(UpdateSet<T> Function(Update<T> update) build) =>
      _whole.runUpdate<T>(build);

  /// Same as [runDelete], on the whole app database.
  static Future<int> delete(DeleteFrom Function(Delete delete) build) => _whole.runDelete(build);

  /// Same as [runTransaction], on the whole app database.
  static Future<T> transaction<T>(Future<T> Function(TransactionScope txn) action) => _whole.runTransaction<T>(action);

  /// Same as [newBatch], on the whole app database.
  static StatementBatch batch() => _whole.newBatch();

  /// Same as [hasTable], on the whole app database.
  static Future<bool> tableExists(String table) => _whole.hasTable(table);

  /// Same as [listTables], on the whole app database.
  static Future<List<String>> tableNames() => _whole.listTables();

  /// Same as [listColumns], on the whole app database.
  static Future<List<ColumnInfo>> columns(String table) => _whole.listColumns(table);

  /// Same as [runCheckpoint], on the whole app database.
  static Future<void> checkpoint() => _whole.runCheckpoint();

  /// Whether [open] has run and [dispose] has not undone it.
  bool get isOpen => _db?.isOpen ?? false;

  /// Whether this database was asked to encrypt its file.
  ///
  /// [open] has already checked that it can, so an open database that says `true` here is encrypted.
  bool get encrypted => _encrypted;

  /// Opens the database file, running whichever of the `onConfigure`, `onCreate`, `onUpgrade`, `onDowngrade` and
  /// `onOpen` callbacks has work to do, and makes this instance usable.
  ///
  /// Calling it twice is harmless: the second call does nothing, and a second call made while the first is still
  /// running waits for it instead of opening another connection.
  ///
  /// Throws an [OpenFailedError] when SQLite cannot open the file, such as a read only open of a file that does not
  /// exist, or fails for a reason no other [StoreError] names. Throws an [EncryptionUnavailableError] when this
  /// database was asked to encrypt and the SQLite it runs on is not SQLCipher, and a [SchemaTooNewError] when a
  /// declared database finds a file written by newer code.
  Future<void> open() {
    if (_db != null) return Future<void>.value();
    return _opening ??= _openFile().whenComplete(() => _opening = null);
  }

  /// Opens the file for [open].
  ///
  /// An encrypted database on a SQLite that is not SQLCipher ignores the key and writes in clear, so a file this call
  /// created is deleted again when that is found out.
  Future<void> _openFile() async {
    try {
      final directory = await _factory.getDatabasesPath();
      final path = p.join(directory, _name);
      final version = _readOnly || _tables != null ? null : _version;
      final existed = !_encrypted || await _factory.databaseExists(path);
      final db = await _factory.openDatabase(
        path,
        options: _encrypted
            ? SqlCipherOpenDatabaseOptions(
                version: version,
                onConfigure: _configure,
                onCreate: _onCreate,
                onUpgrade: _onUpgrade,
                onDowngrade: _onDowngrade,
                onOpen: _onOpen,
                password: _hex(_fingerprint!.derive(_databaseKeyPurpose)),
                readOnly: _readOnly,
                singleInstance: _singleInstance,
              )
            : OpenDatabaseOptions(
                version: version,
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
      if (_encrypted) {
        try {
          await _requireCipher(db);
        } catch (_) {
          await _close(db);
          if (!existed) await _factory.deleteDatabase(path);
          rethrow;
        }
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
      final reason = StoreError.from(error);
      throw reason is UnknownError ? OpenFailedError(reason.message) : reason;
    }
  }

  /// Throws an [EncryptionUnavailableError] unless [db] runs on SQLCipher.
  ///
  /// On any other SQLite the key was ignored and the file is in clear, which is what asking to encrypt it was meant
  /// to prevent.
  Future<void> _requireCipher(Database db) async {
    final rows = await db.rawQuery('PRAGMA cipher_version');
    final version = rows.isEmpty ? null : rows.first.values.first;
    if (version is! String || version.isEmpty) {
      throw EncryptionUnavailableError(
        '$_name was to be encrypted, but the SQLite it runs on is not SQLCipher: '
        'give the LocalDatabase the factory of sqflite_sqlcipher.',
      );
    }
  }

  /// Throws a [StateError] unless [presented] is the fingerprint this database was opened with, which is what opens
  /// the whole-database mechanism.
  void _requireFingerprint(Fingerprint presented) {
    final own = _fingerprint;
    if (own == null) {
      throw StateError(
        '$_name was opened without a fingerprint, so the whole-database mechanism is closed. '
        'Open it with the fingerprint of the app.',
      );
    }
    if (!own.matches(presented)) {
      throw StateError('The fingerprint presented is not the one $_name was opened with.');
    }
  }

  Future<void> _configure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    await _onConfigure?.call(db);
  }

  /// Declares [tables] on this database, which must be open, and creates what they declare: every table that does not
  /// exist yet and every column an existing one gained, under the same rules as [LocalDatabase.declaredForTesting].
  ///
  /// This is how tables reach a database that was opened before anyone knew them, such as the app database, opened
  /// at launch and then handed the project's own tables. Declaring a table again with the same
  /// declaration does nothing. Once a database has been declared any table, it refuses the ones it was not told
  /// about, as one made with [LocalDatabase.declaredForTesting] does.
  ///
  /// Two calls at once run one after the other. A call that fails, because a table is declared differently from
  /// before or because SQLite cannot add a column, leaves the database as it was, tables and file alike.
  ///
  /// Throws a [StateError] on a read only database, on one that is not open, or when a table is already declared
  /// differently.
  Future<void> declareTables(List<TypedTable<Object>> tables) {
    final run = _declaring.then((_) => _declare(tables));
    _declaring = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _declare(List<TypedTable<Object>> tables) async {
    if (_readOnly) throw StateError('$_name is read only: it cannot be declared any table.');
    final db = _requireOpen();
    final before = _tables;
    final known = {for (final table in before ?? const <TypedTable<Object>>[]) table.tableName: table};
    final added = <TypedTable<Object>>[];
    for (final table in tables) {
      final held = known[table.tableName] ?? added.where((other) => other.tableName == table.tableName).firstOrNull;
      if (held == null) {
        added.add(table);
      } else if (held.declaration != table.declaration) {
        throw StateError('${table.tableName} is already declared on $_name, and differently.');
      }
    }
    if (added.isEmpty) return;
    _tables = [...?before, ...added];
    try {
      await _synchronizeSchema(this, db);
    } catch (_) {
      _tables = before;
      rethrow;
    }
  }

  /// Runs [sql] as it is, for what [runInsert], [runQuery], [runUpdate] and [runDelete] do not cover, such as a
  /// `CREATE TABLE`, a `CREATE INDEX` or a schema change inside an `onUpgrade` callback.
  ///
  /// It cannot tell which table [sql] changes, so it tells every watcher that a write happened.
  Future<void> runSql(String sql, [List<Value>? arguments]) => _guarded(() async {
    await _executor().execute(sql, _toNativeArgs(arguments));
    _notifyWrite(null);
  });

  /// Inserts the row that [build] composes from an empty [Insert] and returns its row id.
  Future<int> runInsert<T extends Storable>(InsertValues<T> Function(Insert<T> insert) build) => _guarded(() async {
    final spec = build(Insert<T>._());
    final rowId = await _executor().rawInsert(spec._sql, spec._arguments);
    _notifyWrite({_unquotedIdentifier(spec._table)});
    return rowId;
  });

  /// The rows that [build] selects from an empty [Select], filtered, ordered, paged and decoded as it says.
  ///
  /// Throws a [StateError] if the [QueryFrom] [build] returns was given no `map`.
  Future<List<T>> runQuery<T extends Object>(QueryFrom<T> Function(Select<T> query) build) => _guarded(() async {
    final spec = build(Select<T>._());
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

  /// The rows [sql] selects, run as it is, for a query [runQuery] cannot express such as a join or an aggregate.
  Future<List<RawRow>> runRawQuery(String sql, [List<Value>? arguments]) => _guarded(() async {
    final rows = await _executor().rawQuery(sql, _toNativeArgs(arguments));
    return rows.map(_fromNativeRow).toList();
  });

  /// Updates the rows that [build] composes from an empty [Update] and returns how many changed.
  ///
  /// Watchers of the table are told only when at least one row changed.
  Future<int> runUpdate<T extends Storable>(UpdateSet<T> Function(Update<T> update) build) => _guarded(() async {
    final spec = build(Update<T>._());
    final changed = await _executor().update(
      spec._table,
      _toNativeRow(spec._data.toRow()),
      where: spec._where,
      whereArgs: _toNativeArgs(spec._whereArgs),
      conflictAlgorithm: spec._conflict,
    );
    if (changed > 0) _notifyWrite({_unquotedIdentifier(spec._table)});
    return changed;
  });

  /// Removes the rows that [build] composes from an empty [Delete] and returns how many were removed.
  ///
  /// Watchers of the table are told only when at least one row was removed.
  Future<int> runDelete(DeleteFrom Function(Delete delete) build) => _guarded(() async {
    final spec = build(const Delete._());
    final removed = await _executor().delete(
      spec._table,
      where: spec._where,
      whereArgs: _toNativeArgs(spec._whereArgs),
    );
    if (removed > 0) _notifyWrite({_unquotedIdentifier(spec._table)});
    return removed;
  });

  /// Runs [action] as one transaction: every write inside it commits together, or none of them do if [action] throws.
  ///
  /// Everything [action] asks of this [LocalDatabase], and of a [batch] made from it, joins the transaction as if it
  /// had gone through the [TransactionScope] it is given, because sqflite would otherwise wait forever for a
  /// transaction that is itself waiting for the database. That holds for the code [action] awaits, at any depth. A
  /// [transaction] called inside [action] joins the outer one instead of starting another, so its writes are kept or
  /// undone with the outer transaction, not on their own.
  Future<T> runTransaction<T>(Future<T> Function(TransactionScope txn) action) => _guarded(() async {
    final db = _requireOpen();
    final joined = _joinedTransaction(db);
    if (joined != null) return action(TransactionScope._(joined, this));
    final touched = _TouchedTables();
    final result = await db.transaction(
      (txn) => _inTransaction(db, txn, touched, () => action(TransactionScope._(txn, this))),
    );
    _flush(touched);
    return result;
  });

  /// A batch of writes queued here, none of which touch the database until [StatementBatch.commit] or
  /// [StatementBatch.apply] runs them.
  ///
  /// Prefer it to calling [runInsert], [runUpdate] or [runDelete] once per row in a loop: each of those commits a
  /// transaction of its own, and beyond a handful of rows the time goes into the commits, each of which waits for the
  /// disk.
  StatementBatch newBatch() => StatementBatch._(_executor(), this);

  /// Whether [table] exists in this database.
  Future<bool> hasTable(String table) => _guarded(() async {
    final rows = await runRawQuery("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", [
      Value.varchar(table),
    ]);
    return rows.isNotEmpty;
  });

  /// The name of every table in this database, excluding SQLite's own `sqlite_` tables.
  Future<List<String>> listTables() => runQuery<String>(
    (q) => q
        .from('sqlite_master')
        .select(const ['name'])
        .where((w) => w.raw("type = 'table' AND name NOT LIKE 'sqlite\\_%' ESCAPE '\\'"))
        .map((row) => row['name']!.asString),
  );

  /// Every column of [table], in declaration order, generated columns included.
  ///
  /// Reads `PRAGMA table_xinfo`, which unlike `table_info` lists the generated columns, and falls back to
  /// `table_info` on a SQLite older than 3.26, which answers no row for `table_xinfo` and has no generated column to
  /// leave out.
  ///
  /// The list is empty for a table that does not exist, and [hasTable] tells that answer apart from a table that has
  /// no column.
  Future<List<ColumnInfo>> listColumns(String table) => _guarded(() async {
    final quoted = _quotedIdentifier(table);
    final extended = await runRawQuery('PRAGMA table_xinfo($quoted)');
    final rows = extended.isNotEmpty ? extended : await runRawQuery('PRAGMA table_info($quoted)');
    return rows.map(ColumnInfo._fromRow).toList();
  });

  /// Every way the table [declared] describes differs from the table of that name in this database, empty when they
  /// agree.
  ///
  /// It compares columns (type, `NOT NULL`, primary key position, default, generated), unique and primary keys,
  /// foreign keys (target and actions), the explicit indexes by name and definition, and `STRICT` and
  /// `WITHOUT ROWID`. Only when all of that agrees does it compare the stored `CREATE TABLE` text, the one place where
  /// a `CHECK` constraint, a column collation, the deferral of a foreign key or a generated expression can be seen.
  /// Types, defaults and keys are compared as SQLite itself reads them from the declaration, so two spellings of the
  /// same thing are not reported.
  ///
  /// This reports and never alters: turning a difference into a migration is a decision about the rows on disk that
  /// only a developer can take. It reports [DifferenceKind.foreignKeysDisabled] when the table has a foreign key and
  /// this connection does not enforce them.
  Future<List<SchemaDifference>> differences(DeclaredTable declared) => _guarded(() async {
    final db = _executor();
    final disabled = declared.usesForeignKeys && (await db.rawQuery('PRAGMA foreign_keys')).first['foreign_keys'] == 0;
    final foreignKeys = [
      if (disabled)
        SchemaDifference(
          table: declared.name,
          kind: DifferenceKind.foreignKeysDisabled,
          expected: 'foreign_keys ON',
          actual: 'foreign_keys OFF',
        ),
    ];
    if (!await hasTable(declared.name)) {
      return [
        ...foreignKeys,
        SchemaDifference(
          table: declared.name,
          kind: DifferenceKind.missingTable,
          expected: declared.name,
          actual: null,
        ),
      ];
    }
    final expected = await _factsOfDeclared(declared);
    return [...foreignKeys, ..._compareFacts(declared.name, expected, await _factsOf(db, declared.name))];
  });

  /// Writes every change still sitting in the write-ahead log back into the main database file, and truncates the log.
  ///
  /// Run this before copying the database file for a backup: with `journal_mode = WAL`, some committed data lives
  /// only in the separate `-wal` file until a checkpoint folds it back in.
  Future<void> runCheckpoint() => runSql('PRAGMA wal_checkpoint(TRUNCATE)');

  /// Closes the database.
  ///
  /// Safe to call on an instance that was never opened, and safe to call twice. It waits for an [open] still running,
  /// so that no file is left open behind it. When another [LocalDatabase] with `singleInstance` holds the same file
  /// open, the file stays open until the last of them is disposed.
  @disposeMethod
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

  /// Whether another [LocalDatabase] still holds the file this one shares, so that closing must leave it open.
  ///
  /// It also takes this instance out of the count, so it answers once per open.
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
  Future<T> _atomically<T>(Future<T> Function(Connection session) action) => runTransaction(action);

  /// Tells the watchers of [tables], or of every table when it is `null`, that a write happened.
  ///
  /// Inside a transaction the watchers are told once it commits, and never if it rolls back.
  void _notifyWrite(Set<String>? tables) {
    final active = Zone.current[_transactionZoneKey];
    if (active is _ActiveTransaction && identical(active.database, _db)) {
      active.touched.record(tables);
    } else if (!_writes.isClosed) {
      _writes.add(tables);
    }
  }

  void _flush(_TouchedTables touched) {
    if (touched.everything) {
      _notifyWrite(null);
    } else if (touched.tables.isNotEmpty) {
      _notifyWrite(touched.tables);
    }
  }

  void _requireDeclared(TypedTable<Object> table) {
    final tables = _tables;
    if (tables != null && !tables.any((declared) => declared.tableName == table.tableName)) {
      throw StateError('${table.tableName} is not among the tables this LocalDatabase was declared with.');
    }
  }
}

/// How many [LocalDatabase] hold each shared file open, so that the last one disposed is the one that closes it.
final Map<(DatabaseFactory, String), int> _sharedInstances = {};

/// [bytes] as lower-case hexadecimal text, since the password of an encrypted database is a string.
String _hex(List<int> bytes) => bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

/// The purpose the database key is derived for, so that no other key of the app is the same.
const String _databaseKeyPurpose = 'database';

/// The key under which a running transaction is found by the calls made inside it, which is how they join it.
final Object _transactionZoneKey = Object();

/// The transaction the current zone runs inside, with the connection it belongs to and the tables it wrote so far.
final class _ActiveTransaction {
  const _ActiveTransaction(this.database, this.transaction, this.touched);

  final Database database;
  final Transaction transaction;
  final _TouchedTables touched;
}

/// The tables a transaction wrote, held until it commits.
final class _TouchedTables {
  final Set<String> tables = {};
  bool everything = false;

  void record(Set<String>? written) {
    if (written == null) {
      everything = true;
    } else {
      tables.addAll(written);
    }
  }
}

Transaction? _joinedTransaction(Database database) {
  final active = Zone.current[_transactionZoneKey];
  return active is _ActiveTransaction && identical(active.database, database) ? active.transaction : null;
}

Future<T> _inTransaction<T>(
  Database database,
  Transaction transaction,
  _TouchedTables touched,
  Future<T> Function() action,
) => Zone.current
    .fork(zoneValues: {_transactionZoneKey: _ActiveTransaction(database, transaction, touched)})
    .run(action);

String _quotedIdentifier(String identifier) => '"${identifier.replaceAll('"', '""')}"';

/// The table name inside [quoted], which the builders keep as it is written in SQL (`"todos"`), while the tables a
/// watcher names are spelled `todos`.
String _unquotedIdentifier(String quoted) => quoted.length >= 2 && quoted.startsWith('"') && quoted.endsWith('"')
    ? quoted.substring(1, quoted.length - 1).replaceAll('""', '"')
    : quoted;
