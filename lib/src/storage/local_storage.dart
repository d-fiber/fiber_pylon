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

/// One value SQLite can actually store.
///
/// SQLite's own type system names exactly five storage classes — this closes
/// over them rather than accepting `Object?` and finding out only when
/// sqflite rejects, or silently mangles, something it was never meant to
/// hold. Neither `bool` nor `DateTime` are native to SQLite: use
/// [SqlValue.boolean] for the former (stored as `0`/`1`, the convention every
/// SQLite driver uses, this one included) and pick [integer] (epoch
/// milliseconds) or [text] (ISO-8601) for the latter, whichever a schema's
/// own columns already use — pylon does not guess one for a project that may
/// have already picked the other.
sealed class SqlValue extends Equatable {
  const SqlValue();

  /// A signed integer, up to 64 bits.
  const factory SqlValue.integer(int value) = SqlInteger;

  /// A floating point value.
  const factory SqlValue.real(double value) = SqlReal;

  /// UTF-8 text.
  const factory SqlValue.text(String value) = SqlText;

  /// Raw bytes, stored exactly as given.
  const factory SqlValue.blob(Uint8List value) = SqlBlob;

  /// The absence of a value.
  const factory SqlValue.nil() = SqlNull;

  /// [value] as an [SqlInteger] of `1` or `0`.
  static SqlValue boolean(bool value) => SqlInteger(value ? 1 : 0);

  /// Wraps whatever sqflite itself already handed back for one column.
  ///
  /// Throws an [ArgumentError] if [native] is not one of the native types
  /// sqflite hands back — which should never happen for a value this same
  /// class wrote through [toNative] in the first place.
  factory SqlValue.fromNative(Object? native) => switch (native) {
    null => const SqlNull(),
    final int value => SqlInteger(value),
    final double value => SqlReal(value),
    final String value => SqlText(value),
    final Uint8List value => SqlBlob(value),
    _ => throw ArgumentError.value(native, 'native', 'not a SQLite storage class'),
  };

  /// This value in the native shape sqflite itself accepts and hands back.
  Object? toNative();
}

/// The absence of a value — SQL `NULL`.
final class SqlNull extends SqlValue {
  /// SQL `NULL`. Prefer [SqlValue.nil] over calling this directly.
  const SqlNull();

  @override
  Object? toNative() => null;

  @override
  List<Object?> get props => const [];

  @override
  String toString() => 'SqlValue.nil()';
}

/// A signed integer, up to 64 bits.
final class SqlInteger extends SqlValue {
  /// Wraps [value]. Prefer [SqlValue.integer] over calling this directly.
  const SqlInteger(this.value);

  /// The wrapped integer.
  final int value;

  @override
  Object? toNative() => value;

  @override
  List<Object?> get props => [value];

  @override
  String toString() => 'SqlValue.integer($value)';
}

/// A floating point value.
final class SqlReal extends SqlValue {
  /// Wraps [value]. Prefer [SqlValue.real] over calling this directly.
  const SqlReal(this.value);

  /// The wrapped floating point value.
  final double value;

  @override
  Object? toNative() => value;

  @override
  List<Object?> get props => [value];

  @override
  String toString() => 'SqlValue.real($value)';
}

/// UTF-8 text.
final class SqlText extends SqlValue {
  /// Wraps [value]. Prefer [SqlValue.text] over calling this directly.
  const SqlText(this.value);

  /// The wrapped text.
  final String value;

  @override
  Object? toNative() => value;

  @override
  List<Object?> get props => [value];

  @override
  String toString() => 'SqlValue.text($value)';
}

/// Raw bytes, stored exactly as given.
final class SqlBlob extends SqlValue {
  /// Wraps [value]. Prefer [SqlValue.blob] over calling this directly.
  const SqlBlob(this.value);

  /// The wrapped bytes.
  final Uint8List value;

  @override
  Object? toNative() => value;

  @override
  List<Object?> get props => [value];

  @override
  String toString() => 'SqlValue.blob(${value.length} byte(s))';
}

/// One row, exactly as [LocalDatabase] reads one back or writes one out:
/// column name to [SqlValue]. What a column holds, and what its name means,
/// is entirely the caller's own schema.
typedef LocalRow = Map<String, SqlValue>;

Map<String, Object?> _toNativeRow(LocalRow row) => row.map((column, value) => MapEntry(column, value.toNative()));

LocalRow _fromNativeRow(Map<String, Object?> row) =>
    row.map((column, value) => MapEntry(column, SqlValue.fromNative(value)));

List<Object?>? _toNativeArgs(List<SqlValue>? arguments) => arguments?.map((value) => value.toNative()).toList();

/// One column [LocalDatabase.columns] read out of `PRAGMA table_info`.
final class LocalColumn extends Equatable {
  /// Wraps every field [LocalDatabase.columns] read for one column.
  const LocalColumn({
    required this.name,
    required this.declaredType,
    required this.isNotNull,
    required this.isPrimaryKey,
  });

  /// The column's own name.
  final String name;

  /// The type exactly as the `CREATE TABLE` that declared it wrote it —
  /// empty when the column carries none, since SQLite never requires one.
  final String declaredType;

  /// Whether the column carries a `NOT NULL` constraint.
  final bool isNotNull;

  /// Whether the column is part of the table's primary key.
  final bool isPrimaryKey;

  factory LocalColumn._fromRow(LocalRow row) => LocalColumn(
    name: (row['name'] as SqlText).value,
    declaredType: (row['type'] as SqlText).value,
    isNotNull: (row['notnull'] as SqlInteger).value != 0,
    isPrimaryKey: (row['pk'] as SqlInteger).value != 0,
  );

  @override
  List<Object?> get props => [name, declaredType, isNotNull, isPrimaryKey];
}

/// What went wrong inside SQLite, closed over the handful of causes
/// [DatabaseException] can actually distinguish, through its own
/// message-matching predicates, rather than a project matching sqflite's raw
/// exception text a second time for itself.
sealed class LocalDatabaseError extends Equatable implements Exception {
  const LocalDatabaseError(this.message);

  /// sqflite's own [DatabaseException.toString], verbatim.
  final String message;

  /// Reads which [LocalDatabaseError] [error] actually is, through
  /// [DatabaseException]'s own predicates, answering
  /// [LocalDatabaseUnknownError] when none of them recognise it.
  factory LocalDatabaseError.from(DatabaseException error) {
    final message = error.toString();
    if (error.isUniqueConstraintError()) {
      return LocalDatabaseUniqueConstraintError(message);
    }
    if (error.isNotNullConstraintError()) {
      return LocalDatabaseNotNullConstraintError(message);
    }
    if (error.isNoSuchTableError()) return LocalDatabaseNoSuchTableError(message);
    if (error.isSyntaxError()) return LocalDatabaseSyntaxError(message);
    if (error.isReadOnlyError()) return LocalDatabaseReadOnlyError(message);
    if (error.isDatabaseClosedError()) return LocalDatabaseClosedError(message);
    if (error.isOpenFailedError()) return LocalDatabaseOpenFailedError(message);
    return LocalDatabaseUnknownError(message);
  }

  @override
  List<Object?> get props => [message];

  @override
  String toString() => '$runtimeType($message)';
}

/// A write broke a `UNIQUE` (or a primary key's own implicit one) index.
final class LocalDatabaseUniqueConstraintError extends LocalDatabaseError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const LocalDatabaseUniqueConstraintError(super.message);
}

/// A write left a `NOT NULL` column without a value.
final class LocalDatabaseNotNullConstraintError extends LocalDatabaseError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const LocalDatabaseNotNullConstraintError(super.message);
}

/// A statement named a table that does not exist.
final class LocalDatabaseNoSuchTableError extends LocalDatabaseError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const LocalDatabaseNoSuchTableError(super.message);
}

/// A statement was not valid SQL.
final class LocalDatabaseSyntaxError extends LocalDatabaseError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const LocalDatabaseSyntaxError(super.message);
}

/// A write reached a database [LocalDatabase.open] opened with
/// `readOnly: true`.
final class LocalDatabaseReadOnlyError extends LocalDatabaseError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const LocalDatabaseReadOnlyError(super.message);
}

/// Something reached a [LocalDatabase] after [LocalDatabase.dispose] closed
/// it.
final class LocalDatabaseClosedError extends LocalDatabaseError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const LocalDatabaseClosedError(super.message);
}

/// [LocalDatabase.open] itself failed — a corrupt file, or one this process
/// has no permission to read or write.
final class LocalDatabaseOpenFailedError extends LocalDatabaseError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const LocalDatabaseOpenFailedError(super.message);
}

/// Anything [DatabaseException]'s own predicates do not recognise.
final class LocalDatabaseUnknownError extends LocalDatabaseError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const LocalDatabaseUnknownError(super.message);
}

Future<T> _guarded<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on DatabaseException catch (error) {
    throw LocalDatabaseError.from(error);
  }
}

/// A project's own model that knows how to turn its own fields into a
/// [LocalRow] — the same role [ValkeryJson] plays for [ValkeryStorage],
/// spelled out for a table's own row shape instead of a JSON document.
///
/// [LocalDatabase.insert] and [LocalDatabase.update] never reach into a
/// model's fields themselves: a project's own type declares [toRow] once,
/// and every call site after that passes a plain value instead of a row
/// literal.
abstract interface class LocalRecord {
  /// This value's own fields, ready for [LocalDatabase.insert] or
  /// [LocalDatabase.update] to write.
  LocalRow toRow();
}

/// Opens one [LocalDatabase.insert] (or [LocalBatch.insert]) call. Never
/// constructed directly — [LocalDatabase.insert] hands one to its own
/// callback. The only method here is [into]: nothing can follow `INSERT`
/// before naming a table, so nothing else is offered here either — the
/// compiler refuses a callback that returns [LocalInsert] itself, or
/// anything short of a fully composed [LocalInsertValues].
///
/// ```dart
/// final id = await db.insert<Todo>((i) => i.into('todos').values(todo));
/// ```
final class LocalInsert<T extends LocalRecord> {
  LocalInsert._();

  /// Inserts into [name], the same `INTO` a raw `INSERT INTO ...` names.
  LocalInsertInto<T> into(String name) => LocalInsertInto._(name);
}

/// An [LocalInsert] that has named its table, opened by [LocalInsert.into].
/// The only method here is [values]: a raw `INSERT INTO table` still needs a
/// `VALUES` clause before it means anything, so nothing else is offered
/// here either.
final class LocalInsertInto<T extends LocalRecord> {
  LocalInsertInto._(this._table);

  final String _table;

  /// Inserts [value], read into a row through [LocalRecord.toRow].
  LocalInsertValues<T> values(T value) => LocalInsertValues._(_table, value);
}

/// A fully composed insert, opened by [LocalInsertInto.values] — the only
/// shape [LocalDatabase.insert] accepts back from its own callback, since
/// naming a table and a value is everything a raw `INSERT INTO ... VALUES
/// (...)` needs.
final class LocalInsertValues<T extends LocalRecord> {
  LocalInsertValues._(this._table, this._data, [this._conflict]);

  final String _table;
  final T _data;
  final ConflictAlgorithm? _conflict;

  /// Resolves the conflict, should [values] collide with a row already
  /// there. Left unset, sqflite aborts the whole statement.
  LocalInsertValues<T> onConflict(ConflictAlgorithm algorithm) => LocalInsertValues._(_table, _data, algorithm);
}

/// Opens one [LocalDatabase.query] (or [LocalTransaction.query]) call.
/// Never constructed directly — [LocalDatabase.query] hands one to its own
/// callback. The only method here is [from]: nothing can follow `SELECT`
/// before naming a table, so nothing else is offered here either.
///
/// ```dart
/// final open = await db.query<Todo>(
///   (q) => q.from('todos').where('done = ?', [SqlValue.boolean(false)]).map(Todo.fromRow),
/// );
/// ```
final class LocalQuery<T extends Object> {
  LocalQuery._();

  /// Reads from [name], the same `FROM` a raw `SELECT ... FROM ...` names.
  LocalQueryFrom<T> from(String name) => LocalQueryFrom._(table: name);
}

/// A [LocalQuery] that has named its table, opened by [LocalQuery.from].
/// Every method here answers a new [LocalQueryFrom] rather than changing
/// this one, and — unlike [from] itself — every one of them is optional and
/// may be called in any order, since none of them changes what the next one
/// is allowed to be.
final class LocalQueryFrom<T extends Object> {
  const LocalQueryFrom._({
    required String table,
    T Function(LocalRow row)? fromRow,
    bool distinct = false,
    List<String>? columns,
    String? where,
    List<SqlValue>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) : _table = table,
       _fromRow = fromRow,
       _distinct = distinct,
       _columns = columns,
       _where = where,
       _whereArgs = whereArgs,
       _groupBy = groupBy,
       _having = having,
       _orderBy = orderBy,
       _limit = limit,
       _offset = offset;

  final String _table;
  final T Function(LocalRow row)? _fromRow;
  final bool _distinct;
  final List<String>? _columns;
  final String? _where;
  final List<SqlValue>? _whereArgs;
  final String? _groupBy;
  final String? _having;
  final String? _orderBy;
  final int? _limit;
  final int? _offset;

  /// Decodes each selected row into a [T] with [fromRow]. Required: nothing
  /// here guesses how a row and a model relate.
  LocalQueryFrom<T> map(T Function(LocalRow row) fromRow) => _copyWith(fromRow: fromRow);

  /// Skips a row that duplicates one already read, across the columns
  /// [select] named.
  LocalQueryFrom<T> distinct([bool value = true]) => _copyWith(distinct: value);

  /// Reads only [columns], instead of every column the table declares.
  LocalQueryFrom<T> select(List<String> columns) => _copyWith(columns: columns);

  /// Keeps only the rows [clause] matches, every `?` in it bound to
  /// [arguments] in order.
  ///
  /// `WHERE column = ?` with a `null` argument never matches a row where
  /// `column IS NULL` — write `column IS NULL` into [clause] directly for
  /// that, the same rule plain SQL follows.
  LocalQueryFrom<T> where(String clause, [List<SqlValue>? arguments]) =>
      _copyWith(where: clause, whereArgs: arguments);

  /// Groups matching rows by [clause] before [having] and [map] see them.
  LocalQueryFrom<T> groupBy(String clause) => _copyWith(groupBy: clause);

  /// Keeps only the groups [clause] matches. Meaningless without [groupBy].
  LocalQueryFrom<T> having(String clause) => _copyWith(having: clause);

  /// Orders the result by [clause].
  LocalQueryFrom<T> orderBy(String clause) => _copyWith(orderBy: clause);

  /// Reads at most [count] rows.
  LocalQueryFrom<T> limit(int count) => _copyWith(limit: count);

  /// Skips the first [count] matching rows, applied after [limit].
  LocalQueryFrom<T> offset(int count) => _copyWith(offset: count);

  LocalQueryFrom<T> _copyWith({
    T Function(LocalRow row)? fromRow,
    bool? distinct,
    List<String>? columns,
    String? where,
    List<SqlValue>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => LocalQueryFrom._(
    table: _table,
    fromRow: fromRow ?? _fromRow,
    distinct: distinct ?? _distinct,
    columns: columns ?? _columns,
    where: where ?? _where,
    whereArgs: whereArgs ?? _whereArgs,
    groupBy: groupBy ?? _groupBy,
    having: having ?? _having,
    orderBy: orderBy ?? _orderBy,
    limit: limit ?? _limit,
    offset: offset ?? _offset,
  );

  T Function(LocalRow row) get _requiredFromRow => _fromRow ?? (throw StateError('LocalQueryFrom.map was never set.'));
}

/// Opens one [LocalDatabase.update] (or [LocalBatch.update]) call. Never
/// constructed directly — [LocalDatabase.update] hands one to its own
/// callback. The only method here is [table]: nothing can follow `UPDATE`
/// before naming a table, so nothing else is offered here either.
///
/// ```dart
/// final changed = await db.update<Todo>(
///   (u) => u.table('todos').set(done).where('id = ?', [SqlValue.integer(id)]),
/// );
/// ```
final class LocalUpdate<T extends LocalRecord> {
  LocalUpdate._();

  /// Updates rows in [name], the same table name a raw `UPDATE table` names.
  LocalUpdateTable<T> table(String name) => LocalUpdateTable._(name);
}

/// A [LocalUpdate] that has named its table, opened by [LocalUpdate.table].
/// The only method here is [set]: a raw `UPDATE table` still needs a `SET`
/// clause before it means anything, so nothing else is offered here either.
final class LocalUpdateTable<T extends LocalRecord> {
  LocalUpdateTable._(this._table);

  final String _table;

  /// Writes [value], read into a row through [LocalRecord.toRow], over
  /// every matched row.
  LocalUpdateSet<T> set(T value) => LocalUpdateSet._(_table, value);
}

/// A fully composed update, opened by [LocalUpdateTable.set] — the only
/// shape [LocalDatabase.update] accepts back from its own callback. [where]
/// and [onConflict] refine it further and may be called in either order,
/// since neither changes what the other is allowed to be.
final class LocalUpdateSet<T extends LocalRecord> {
  LocalUpdateSet._(this._table, this._data, [this._where, this._whereArgs, this._conflict]);

  final String _table;
  final T _data;
  final String? _where;
  final List<SqlValue>? _whereArgs;
  final ConflictAlgorithm? _conflict;

  /// Keeps only the rows [clause] matches, every `?` in it bound to
  /// [arguments] in order. Every row in the table is matched when this is
  /// never called.
  LocalUpdateSet<T> where(String clause, [List<SqlValue>? arguments]) =>
      LocalUpdateSet._(_table, _data, clause, arguments, _conflict);

  /// Resolves the conflict, should [set] collide with a row already there.
  /// Left unset, sqflite aborts the whole statement.
  LocalUpdateSet<T> onConflict(ConflictAlgorithm algorithm) =>
      LocalUpdateSet._(_table, _data, _where, _whereArgs, algorithm);
}

/// Opens one [LocalDatabase.delete] (or [LocalBatch.delete]) call. Never
/// constructed directly — [LocalDatabase.delete] hands one to its own
/// callback. The only method here is [from]: nothing can follow `DELETE`
/// before naming a table, so nothing else is offered here either.
///
/// ```dart
/// final removed = await db.delete((d) => d.from('todos').where('done = ?', [SqlValue.boolean(true)]));
/// ```
final class LocalDelete {
  const LocalDelete._();

  /// Removes rows from [name], the same `FROM` a raw `DELETE FROM ...` names.
  LocalDeleteFrom from(String name) => LocalDeleteFrom._(name);
}

/// A [LocalDelete] that has named its table, opened by [LocalDelete.from] —
/// already a fully composed delete, since `WHERE` is genuinely optional on
/// a raw `DELETE FROM table` (it removes every row without one).
final class LocalDeleteFrom {
  LocalDeleteFrom._(this._table, [this._where, this._whereArgs]);

  final String _table;
  final String? _where;
  final List<SqlValue>? _whereArgs;

  /// Keeps only the rows [clause] matches, every `?` in it bound to
  /// [arguments] in order. Every row in the table is removed when this is
  /// never called.
  LocalDeleteFrom where(String clause, [List<SqlValue>? arguments]) => LocalDeleteFrom._(_table, clause, arguments);
}

/// A local SQLite database, opened once and reused — the same open, create,
/// migrate and close lifecycle every sqflite-backed store in pylon would
/// otherwise hand-roll for itself.
///
/// Unlike [LocalStorage] — a key-value cache with one fixed table it never
/// lets a caller see the shape of — this assumes nothing about what tables
/// exist or what a row looks like: a project (or another pylon primitive)
/// supplies its own schema through [onCreate] and [onUpgrade], then reads
/// and writes it through [insert], [query], [update], [delete], raw SQL and
/// [transaction], typed throughout on [SqlValue] and [LocalRow] rather than
/// `Object?`. This adds only the lifecycle sqflite leaves to the caller; it
/// never reinterprets a column, a table name or a query as meaning
/// something.
///
/// ```dart
/// class Todo implements LocalRecord {
///   Todo({required this.title, required this.done});
///   final String title;
///   final bool done;
///
///   static Todo fromRow(LocalRow row) => Todo(
///     title: (row['title'] as SqlText).value,
///     done: (row['done'] as SqlInteger).value != 0,
///   );
///
///   @override
///   LocalRow toRow() => {'title': SqlValue.text(title), 'done': SqlValue.boolean(done)};
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
/// below throws the [LocalDatabaseError] [LocalDatabaseError.from] reads out
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

  /// Inserts one row, composed by [build] from an empty [LocalInsert] —
  /// [build] must return a fully composed [LocalInsertValues], the same way
  /// a raw `INSERT` needs an `INTO` and a `VALUES` before it means anything
  /// — answering the row id sqflite assigned.
  Future<int> insert<T extends LocalRecord>(LocalInsertValues<T> Function(LocalInsert<T> insert) build) =>
      _guarded(() {
        final spec = build(LocalInsert<T>._());
        return _requireOpen().insert(
          spec._table,
          _toNativeRow(spec._data.toRow()),
          conflictAlgorithm: spec._conflict,
        );
      });

  /// Reads rows, filtered, ordered, paged and decoded exactly as [build]
  /// composes it from an empty [LocalQuery] — [build] must return a
  /// [LocalQueryFrom], the same way a raw `SELECT` needs a `FROM` before it
  /// means anything.
  Future<List<T>> query<T extends Object>(LocalQueryFrom<T> Function(LocalQuery<T> query) build) =>
      _guarded(() async {
        final spec = build(LocalQuery<T>._());
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
  Future<List<LocalRow>> rawQuery(String sql, [List<SqlValue>? arguments]) => _guarded(() async {
    final rows = await _requireOpen().rawQuery(sql, _toNativeArgs(arguments));
    return rows.map(_fromNativeRow).toList();
  });

  /// Writes one row over every row matched, composed by [build] from an
  /// empty [LocalUpdate] — [build] must return a [LocalUpdateSet], the same
  /// way a raw `UPDATE table` needs a `SET` before it means anything —
  /// answering how many rows changed.
  Future<int> update<T extends LocalRecord>(LocalUpdateSet<T> Function(LocalUpdate<T> update) build) => _guarded(() {
    final spec = build(LocalUpdate<T>._());
    return _requireOpen().update(
      spec._table,
      _toNativeRow(spec._data.toRow()),
      where: spec._where,
      whereArgs: _toNativeArgs(spec._whereArgs),
      conflictAlgorithm: spec._conflict,
    );
  });

  /// Removes every row matched, composed by [build] from an empty
  /// [LocalDelete] — [build] must return a [LocalDeleteFrom], the same way
  /// a raw `DELETE` needs a `FROM` before it means anything — answering how
  /// many rows were removed.
  Future<int> delete(LocalDeleteFrom Function(LocalDelete delete) build) => _guarded(() {
    final spec = build(const LocalDelete._());
    return _requireOpen().delete(spec._table, where: spec._where, whereArgs: _toNativeArgs(spec._whereArgs));
  });

  /// Runs [action] as one transaction: every write inside it commits
  /// together, or none of them do if [action] throws.
  ///
  /// [action] never reaches for this [LocalDatabase] itself — only the
  /// [LocalTransaction] it is given — since sqflite deadlocks a transaction
  /// that touches the database it is running against directly instead of
  /// through the transaction object.
  Future<T> transaction<T>(Future<T> Function(LocalTransaction txn) action) =>
      _guarded(() => _requireOpen().transaction((txn) => action(LocalTransaction._(txn))));

  /// Starts a batch: a sequence of writes queued here, none of which touch
  /// the database until [LocalBatch.commit] or [LocalBatch.apply] runs them.
  ///
  /// Prefer this over calling [insert] (or [update], or [delete]) once per
  /// row in a loop: each of those otherwise opens and commits its own
  /// implicit transaction, which for anything beyond a handful of rows is
  /// the difference between finishing instantly and taking seconds, since
  /// every commit costs its own fsync.
  LocalBatch batch() => LocalBatch._(_requireOpen().batch());

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
  Future<List<LocalColumn>> columns(String table) => _guarded(() async {
    final rows = await rawQuery('PRAGMA table_info(${_quotedIdentifier(table)})');
    return rows.map(LocalColumn._fromRow).toList();
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
      throw StateError('LocalDatabase is not open. Call open() first.');
    }
    return db;
  }
}

String _quotedIdentifier(String identifier) => '"${identifier.replaceAll('"', '""')}"';

/// The same [LocalDatabase.insert], [LocalDatabase.query],
/// [LocalDatabase.update] and [LocalDatabase.delete] a [LocalDatabase]
/// offers, scoped to one [LocalDatabase.transaction]. Never constructed
/// directly; [LocalDatabase.transaction] hands one to its own callback.
final class LocalTransaction {
  LocalTransaction._(this._txn);

  final Transaction _txn;

  /// See [LocalDatabase.execute].
  Future<void> execute(String sql, [List<SqlValue>? arguments]) =>
      _guarded(() => _txn.execute(sql, _toNativeArgs(arguments)));

  /// See [LocalDatabase.insert].
  Future<int> insert<T extends LocalRecord>(LocalInsertValues<T> Function(LocalInsert<T> insert) build) =>
      _guarded(() {
        final spec = build(LocalInsert<T>._());
        return _txn.insert(spec._table, _toNativeRow(spec._data.toRow()), conflictAlgorithm: spec._conflict);
      });

  /// See [LocalDatabase.query].
  Future<List<T>> query<T extends Object>(LocalQueryFrom<T> Function(LocalQuery<T> query) build) =>
      _guarded(() async {
        final spec = build(LocalQuery<T>._());
        final rows = await _txn.query(
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

  /// See [LocalDatabase.rawQuery].
  Future<List<LocalRow>> rawQuery(String sql, [List<SqlValue>? arguments]) => _guarded(() async {
    final rows = await _txn.rawQuery(sql, _toNativeArgs(arguments));
    return rows.map(_fromNativeRow).toList();
  });

  /// See [LocalDatabase.update].
  Future<int> update<T extends LocalRecord>(LocalUpdateSet<T> Function(LocalUpdate<T> update) build) => _guarded(() {
    final spec = build(LocalUpdate<T>._());
    return _txn.update(
      spec._table,
      _toNativeRow(spec._data.toRow()),
      where: spec._where,
      whereArgs: _toNativeArgs(spec._whereArgs),
      conflictAlgorithm: spec._conflict,
    );
  });

  /// See [LocalDatabase.delete].
  Future<int> delete(LocalDeleteFrom Function(LocalDelete delete) build) => _guarded(() {
    final spec = build(const LocalDelete._());
    return _txn.delete(spec._table, where: spec._where, whereArgs: _toNativeArgs(spec._whereArgs));
  });
}

/// A sequence of writes queued against a [LocalDatabase], none of which
/// touch it until [commit] or [apply] runs them. Never constructed directly;
/// [LocalDatabase.batch] hands one back.
final class LocalBatch {
  LocalBatch._(this._batch);

  final Batch _batch;

  /// Queues an [LocalDatabase.insert].
  void insert<T extends LocalRecord>(LocalInsertValues<T> Function(LocalInsert<T> insert) build) {
    final spec = build(LocalInsert<T>._());
    _batch.insert(spec._table, _toNativeRow(spec._data.toRow()), conflictAlgorithm: spec._conflict);
  }

  /// Queues an [LocalDatabase.update].
  void update<T extends LocalRecord>(LocalUpdateSet<T> Function(LocalUpdate<T> update) build) {
    final spec = build(LocalUpdate<T>._());
    _batch.update(
      spec._table,
      _toNativeRow(spec._data.toRow()),
      where: spec._where,
      whereArgs: _toNativeArgs(spec._whereArgs),
      conflictAlgorithm: spec._conflict,
    );
  }

  /// Queues a [LocalDatabase.delete].
  void delete(LocalDeleteFrom Function(LocalDelete delete) build) {
    final spec = build(const LocalDelete._());
    _batch.delete(spec._table, where: spec._where, whereArgs: _toNativeArgs(spec._whereArgs));
  }

  /// Queues an [LocalDatabase.execute].
  void execute(String sql, [List<SqlValue>? arguments]) => _batch.execute(sql, _toNativeArgs(arguments));

  /// Queues a [LocalDatabase.query]. Its rows land at this call's own
  /// position in [commit]'s or [apply]'s result list, as a raw
  /// `List<Map<String, Object?>>` — sqflite's own batch API answers every
  /// queued statement through one shared, loosely typed result list, so
  /// this is the one place [LocalBatch] cannot hand back a [LocalRow] the
  /// way every other method here does; decode it with
  /// [SqlValue.fromNative] per column.
  void query(
    String table, {
    bool distinct = false,
    List<String>? columns,
    String? where,
    List<SqlValue>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => _batch.query(
    table,
    distinct: distinct,
    columns: columns,
    where: where,
    whereArgs: _toNativeArgs(whereArgs),
    groupBy: groupBy,
    having: having,
    orderBy: orderBy,
    limit: limit,
    offset: offset,
  );

  /// Runs every statement queued so far as one atomic unit: either they all
  /// land, or — unless [continueOnError] is `true` — none of them do.
  ///
  /// [noResult] skips collecting each statement's own result (an inserted
  /// row id, an affected-row count, a query's rows), worth setting for a
  /// large batch that only cares whether it succeeded.
  Future<List<Object?>> commit({bool? exclusive, bool? noResult, bool? continueOnError}) =>
      _guarded(() => _batch.commit(exclusive: exclusive, noResult: noResult, continueOnError: continueOnError));

  /// Runs every statement queued so far without wrapping them in a
  /// transaction sqflite manages — faster, but with no all-or-nothing
  /// guarantee if one fails partway through. Prefer [commit] unless this
  /// batch is already running inside a [LocalDatabase.transaction] of its
  /// own, or another transaction not managed through this class.
  Future<List<Object?>> apply({bool? noResult, bool? continueOnError}) =>
      _guarded(() => _batch.apply(noResult: noResult, continueOnError: continueOnError));
}
