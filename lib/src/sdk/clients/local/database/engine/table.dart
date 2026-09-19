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

part of 'database.dart';

final DatabaseCodec<int> _integerCodec = DatabaseCodec<int>(
  storage: ColumnType.integer,
  encode: DatabaseType.integer,
  decode: (stored) => stored.asInt,
);

final DatabaseCodec<double> _realCodec = DatabaseCodec<double>(
  storage: ColumnType.real,
  encode: DatabaseType.real,
  decode: (stored) => stored.asDouble,
);

final DatabaseCodec<String> _textCodec = DatabaseCodec<String>(
  storage: ColumnType.text,
  encode: DatabaseType.varchar,
  decode: (stored) => stored.asString,
);

final DatabaseCodec<Uint8List> _blobCodec = DatabaseCodec<Uint8List>(
  storage: ColumnType.blob,
  encode: DatabaseType.blob,
  decode: (stored) => stored.asBytes,
);

final DatabaseCodec<bool> _booleanCodec = DatabaseCodec<bool>(
  storage: ColumnType.integer,
  encode: DatabaseType.boolean,
  decode: (stored) => stored.asBoolean,
);

final DatabaseCodec<DateTime> _timestampCodec = DatabaseCodec<DateTime>(
  storage: ColumnType.integer,
  encode: (value) => DatabaseType.timestamp(value.millisecondsSinceEpoch),
  decode: (stored) => stored.asDateTime,
);

final DatabaseCodec<Date> _dateCodec = DatabaseCodec<Date>(
  storage: ColumnType.integer,
  encode: DatabaseType.date,
  decode: (stored) => stored.asDate,
);

final DatabaseCodec<Time> _timeCodec = DatabaseCodec<Time>(
  storage: ColumnType.text,
  encode: DatabaseType.time,
  decode: (stored) => stored.asTime,
);

final DatabaseCodec<UuidValue> _uuidCodec = DatabaseCodec<UuidValue>(
  storage: ColumnType.text,
  encode: DatabaseType.uuid,
  decode: (stored) => stored.asUuid,
);

/// Opens the columns of one table, through [DatabaseTable.column]. Each method
/// takes the name the column has in the database, and answers a
/// [DatabaseField] typed with the Dart type that column holds.
///
/// A column refuses NULL until [DatabaseField.nullable] says otherwise.
final class DatabaseColumns {
  const DatabaseColumns._(this._table, this._isolated);

  final String _table;
  final bool _isolated;

  /// An integer primary key the database numbers itself, and never numbers
  /// twice: a deleted row's key is not handed out again.
  DatabaseKey<int> key([String name = 'id']) => DatabaseKey<int>._(
    _table,
    name,
    _FieldDefinition(codec: _integerCodec._erased, isPrimary: true, isAutoincrement: true, isolated: _isolated),
  );

  /// A UUID primary key. The engine generates a random one on insert when a
  /// record does not carry one yet.
  DatabaseKey<UuidValue> uuidKey([String name = 'id']) => DatabaseKey<UuidValue>._(
    _table,
    name,
    _FieldDefinition(
      codec: _uuidCodec._erased,
      isPrimary: true,
      generator: DatabaseType.randomUuid,
      isolated: _isolated,
    ),
  );

  /// A whole number of up to 64 bits.
  DatabaseField<int> integer(String name) => custom(name, _integerCodec);

  /// A floating point number.
  DatabaseField<double> real(String name) => custom(name, _realCodec);

  /// Text.
  DatabaseField<String> text(String name) => custom(name, _textCodec);

  /// Raw bytes.
  DatabaseField<Uint8List> blob(String name) => custom(name, _blobCodec);

  /// A boolean, stored as `1` or `0`.
  DatabaseField<bool> boolean(String name) => custom(name, _booleanCodec);

  /// An instant, stored as milliseconds since the Unix epoch and read back as
  /// a UTC [DateTime].
  DatabaseField<DateTime> timestamp(String name) => custom(name, _timestampCodec);

  /// A calendar date with no time of day, the same on every device.
  DatabaseField<Date> date(String name) => custom(name, _dateCodec);

  /// A time of day with no calendar date.
  DatabaseField<Time> time(String name) => custom(name, _timeCodec);

  /// A UUID, stored as its canonical text.
  DatabaseField<UuidValue> uuid(String name) => custom(name, _uuidCodec);

  /// One member of [values], stored by name, so that reordering the enum never
  /// changes what a stored row means.
  DatabaseField<E> enumeration<E extends Enum>(String name, List<E> values) => custom(
    name,
    DatabaseCodec<E>(storage: ColumnType.text, encode: DatabaseType.enum_, decode: (stored) => stored.asEnum(values)),
  );

  /// A list of native JSON values, stored as JSON text.
  DatabaseField<List<T>> list<T>(String name) => custom(
    name,
    DatabaseCodec<List<T>>(storage: ColumnType.text, encode: DatabaseType.list, decode: (stored) => stored.asList<T>()),
  );

  /// A value of your own type, stored as JSON text through [json].
  DatabaseField<T> json<T extends Object>(String name, Json<T> json) =>
      custom(name, DatabaseCodec<T>(storage: ColumnType.text, encode: json.encode, decode: json.decode));

  /// A value of your own type, stored the way [codec] says.
  DatabaseField<V> custom<V extends Object>(String name, DatabaseCodec<V> codec) =>
      DatabaseField<V>._(_table, name, _FieldDefinition(codec: codec._erased, isolated: _isolated));
}

/// One row of a table as a query read it, handed to [DatabaseTable.read].
///
/// Calling it with a column answers that column's value already decoded to
/// the Dart type of the column: `row(title)` is a `String`, `row(due)` is a
/// `Date?` when `due` accepts NULL.
final class DatabaseReader {
  const DatabaseReader._(this._table, this._row);

  final String _table;
  final DatabaseRow _row;

  /// The value [field] holds in this row.
  ///
  /// Throws a [StateError] when [field] belongs to another table, or when it
  /// holds NULL although it was not declared nullable.
  V call<V>(DatabaseField<V> field) {
    if (field.table != _table) throw StateError('$field was read through a row of $_table.');
    final stored = _row[field.name];
    if (stored == null) throw StateError('$field is not among the columns this row was read with.');
    return field._decode(stored);
  }
}

/// A table of the database and the record type [R] its rows map to. A
/// project declares one subclass per table, and that is all the schema and
/// the mapping it writes.
///
/// ```dart
/// final class Todos extends DatabaseKeyedTable<Todo, int> {
///   Todos() : super('todos');
///
///   late final id = column.key();
///   late final title = column.text('title');
///   late final done = column.boolean('done').defaultsTo(false);
///   late final due = column.date('due').nullable();
///
///   @override
///   List<DatabaseField<Object?>> get columns => [id, title, done, due];
///
///   @override
///   Todo read(DatabaseReader row) => Todo(id: row(id), title: row(title), done: row(done), due: row(due));
///
///   @override
///   List<DatabaseAssignment> write(Todo todo) =>
///       [id.toOrGenerate(todo.id), title.to(todo.title), done.to(todo.done), due.to(todo.due)];
/// }
///
/// final todos = Todos();
/// ```
///
/// Declare the table once, at top level, hand it to [LocalDatabase.declared],
/// and read and write it through [on]. The names [tableName], [column],
/// [columns], [primaryKey], [uniques], [indexes], [read], [write], [on] and
/// [declaration] belong to this class, so a column cannot be a field called
/// one of them.
abstract class DatabaseTable<R extends Object> {
  /// A table called [tableName] in the database.
  DatabaseTable(this.tableName);

  /// The name of this table in the database.
  final String tableName;

  /// Opens the columns of this table. Each `late final` field of the subclass
  /// is one call.
  late final DatabaseColumns column = DatabaseColumns._(tableName, tunnel == Tunnel.isolated);

  /// Whose rows this table holds: [Tunnel.shared], one copy for everyone (the
  /// default), or [Tunnel.isolated], where every [Tenant] has rows of its own.
  ///
  /// An isolated table gains a hidden column that holds the tenant of each row,
  /// and the engine adds it to every read and write, so no query can reach
  /// another tenant's rows by leaving a condition out. The key of such a table
  /// is unique per tenant, not across them, and so are its unique columns; an
  /// index and a foreign key to another isolated table are per tenant too.
  /// Changing the tunnel of a table that already holds rows needs a migration.
  Tunnel get tunnel => Tunnel.shared;

  /// Every column of this table, in the order they are created.
  ///
  /// A column missing from here is not created, and any read, write or filter
  /// that uses it throws a [StateError] naming it.
  List<DatabaseField<Object?>> get columns;

  /// The columns that together make the primary key, for a table with no
  /// single key column, such as one that links two others.
  List<DatabaseField<Object?>> get primaryKey => const [];

  /// Each list of columns that must not repeat together across two rows.
  List<List<DatabaseField<Object?>>> get uniques => const [];

  /// Each list of columns worth an index, for a column filtered or ordered on
  /// often. A column that references another table is not indexed unless it
  /// is listed here.
  List<List<DatabaseField<Object?>>> get indexes => const [];

  /// Builds a record from one row.
  R read(DatabaseReader row);

  /// The columns of [record] this table writes, each paired with its value.
  List<DatabaseAssignment> write(R record);

  /// This table read and written through [session], a [LocalDatabase] or the
  /// [DatabaseTransaction] of one of its transactions.
  DatabaseTableAccess<R> on(DatabaseSession session) {
    session._database._requireDeclared(this);
    return DatabaseTableAccess<R>._(session, this);
  }

  /// This table across every tenant, read and written through [session]: the
  /// whole-database mechanism, which is a separate entry point from [on], not a
  /// wider view of it. See [DatabaseWholeRows].
  ///
  /// Reaching the whole database takes the app's [Fingerprint], which must be
  /// the one the database was opened with: throws a [StateError] otherwise.
  DatabaseWholeRows<R> onWholeDatabase(DatabaseSession session, Fingerprint fingerprint) {
    session._database._requireDeclared(this);
    session._database._requireFingerprint(fingerprint);
    return DatabaseWholeRows<R>._(session, this);
  }

  /// The `CREATE TABLE` this class declares, as the schema library renders it.
  late final DeclaredTable declaration = _declare();

  DatabaseField<Object?>? get _keyField => null;

  DeclaredTable _declare() {
    final names = <String>{};
    for (final field in columns) {
      _requireOwned(field);
      if (!names.add(field.name)) throw StateError('$tableName lists ${field.name} twice in columns.');
    }
    for (final field in [
      ...primaryKey,
      for (final unique in uniques) ...unique,
      for (final index in indexes) ...index,
    ]) {
      _requireOwned(field);
    }
    return tunnel == Tunnel.isolated ? _declareIsolated(names) : _declareShared();
  }

  DeclaredTable _declareShared() {
    for (final field in columns) {
      if (field._definition.referencesIsolated) {
        throw StateError(
          '$field points at a column of an isolated table, but $tableName is shared: '
          'a row everyone sees would point at a row only one tenant sees.',
        );
      }
    }
    final builder = TableBuilder(tableName);
    if (primaryKey.isNotEmpty) builder.primaryKey((pk) => pk.columns([for (final field in primaryKey) field.name]));
    builder.uniques(
      (u) => [
        for (final unique in uniques) u.columns([for (final field in unique) field.name]),
      ],
    );
    builder.indexes(
      (i) => [
        for (final index in indexes)
          i.name('${tableName}_${index.map((field) => field.name).join('_')}_idx').columns([
            for (final field in index) IndexColumn.named(field.name),
          ]),
      ],
    );
    return builder.columns((c) => {for (final field in columns) field.name: field._definition.builder(c)});
  }

  /// The table as an isolated one is created: a hidden tenant column joins
  /// the key, every unique constraint, every index and every foreign key to
  /// another isolated table, so that two tenants never collide, and a row can
  /// never point at another tenant's.
  DeclaredTable _declareIsolated(Set<String> names) {
    if (names.contains(_tenantColumn)) {
      throw StateError('$tableName declares a column called $_tenantColumn, which an isolated table reserves.');
    }
    final keyColumns = [
      for (final field in columns)
        if (field.isPrimary) field,
    ];
    final autoKey = keyColumns.any((field) => field._definition.isAutoincrement);
    // An auto-numbered key stays alone the primary key, since SQLite only
    // numbers a single-column one: the numbers are then unique across tenants,
    // and the tenant joins a unique constraint that foreign keys can point at.
    final composedKey = <String>[
      if (!autoKey && keyColumns.isNotEmpty) ...keyColumns.map((field) => field.name),
      if (!autoKey && keyColumns.isEmpty) ...primaryKey.map((field) => field.name),
    ];
    final uniqueColumns = [
      for (final field in columns)
        if (field._definition.isUnique) field.name,
    ];
    final references = [
      for (final field in columns)
        if (field._definition.reference != null && field._definition.referencesIsolated) field,
    ];

    final builder = TableBuilder(tableName);
    if (composedKey.isNotEmpty) builder.primaryKey((pk) => pk.columns([_tenantColumn, ...composedKey]));
    builder.uniques(
      (u) => [
        if (autoKey) u.columns([_tenantColumn, keyColumns.first.name]),
        for (final name in uniqueColumns) u.columns([_tenantColumn, name]),
        for (final unique in uniques) u.columns([_tenantColumn, for (final field in unique) field.name]),
      ],
    );
    builder.indexes(
      (i) => [
        if (autoKey) i.name('${tableName}___tenant_idx').columns(const [IndexColumn.named(_tenantColumn)]),
        for (final index in indexes)
          i.name('${tableName}_${index.map((field) => field.name).join('_')}_idx').columns([
            const IndexColumn.named(_tenantColumn),
            for (final field in index) IndexColumn.named(field.name),
          ]),
      ],
    );
    if (references.isNotEmpty) {
      builder.foreignKeys((f) => [for (final field in references) _tenantForeignKey(f, field)]);
    }
    return builder.columns((c) {
      final map = <String, ColumnBuilder<dynamic, DatabaseType>>{};
      for (final field in columns) {
        final definition = field._definition;
        map[field.name] = definition.builder(
          c,
          keepPrimary: definition.isAutoincrement || !definition.isPrimary,
          keepUnique: false,
          keepReference: !definition.referencesIsolated,
        );
      }
      final tenant = c.text().default_(const Varchar(''));
      tenant.isNullable(false);
      map[_tenantColumn] = tenant;
      return map;
    });
  }

  TableForeignKeyBuilder _tenantForeignKey(TableForeignKeyFactory factory, DatabaseField<Object?> field) {
    final reference = field._definition.reference!;
    final referenced = reference.column;
    if (referenced == null) {
      throw StateError('$field references ${reference.table} without naming the column.');
    }
    final foreignKey = factory.columns([_tenantColumn, field.name]).references(reference.table, [
      _tenantColumn,
      referenced,
    ]);
    final onDelete = reference.onDelete;
    if (onDelete != null) foreignKey.onDelete(onDelete);
    final onUpdate = reference.onUpdate;
    if (onUpdate != null) foreignKey.onUpdate(onUpdate);
    final deferral = reference.deferral;
    if (deferral != null) foreignKey.deferrable(deferral);
    return foreignKey;
  }

  void _requireOwned(DatabaseField<Object?> field) {
    if (field.table != tableName || !columns.contains(field)) {
      throw StateError('$field is not listed in the columns of $tableName.');
    }
  }

  Map<String, DatabaseType> _rowOf(R record, {required bool generateKey}) {
    final row = _valuesOf(write(record));
    final key = _keyField;
    if (generateKey && key is DatabaseKey<Object> && !row.containsKey(key.name)) {
      final generated = key._generate();
      if (generated != null) row[key.name] = generated;
    }
    return row;
  }

  Map<String, DatabaseType> _valuesOf(List<DatabaseAssignment> assignments) {
    final row = <String, DatabaseType>{};
    for (final assignment in assignments) {
      _requireOwned(assignment.field);
      final value = assignment._value;
      if (value == null) continue;
      if (assignment._isIncrement) {
        throw StateError(
          '${assignment.field} is incremented, which only an update can do: a new row has nothing to add to.',
        );
      }
      if (row.containsKey(assignment.field.name)) {
        throw StateError('${assignment.field} is written twice for one record.');
      }
      row[assignment.field.name] = value;
    }
    return row;
  }

  /// What an update of [assignments] sets, as the `SET` clauses and the
  /// arguments they bind, in order.
  ({List<String> clauses, List<DatabaseType> arguments}) _updateOf(List<DatabaseAssignment> assignments) {
    final written = <String>{};
    final clauses = <String>[];
    final arguments = <DatabaseType>[];
    for (final assignment in assignments) {
      _requireOwned(assignment.field);
      final value = assignment._value;
      if (value == null) continue;
      final name = assignment.field.name;
      if (!written.add(name)) throw StateError('${assignment.field} is written twice by one update.');
      final quoted = _quotedIdentifier(name);
      clauses.add(assignment._isIncrement ? '$quoted = COALESCE($quoted, 0) + ?' : '$quoted = ?');
      arguments.add(value);
    }
    return (clauses: clauses, arguments: arguments);
  }

  String get _columnList => columns.map((field) => _quotedIdentifier(field.name)).join(', ');

  R _fromRow(DatabaseRow row) => read(DatabaseReader._(tableName, row));
}

/// A [DatabaseTable] whose rows are told apart by one primary key column of
/// the Dart type [K], which unlocks reading a row by its key, upserting a
/// record and deleting a row by its key.
///
/// The key is the one column of [columns] opened as a key, through
/// [DatabaseColumns.key], [DatabaseColumns.uuidKey] or [DatabaseField.primaryKey],
/// and its Dart type must be [K]. Both are checked when the schema is
/// declared, which is the first time the database opens.
abstract class DatabaseKeyedTable<R extends Object, K extends Object> extends DatabaseTable<R> {
  /// A keyed table called [tableName] in the database.
  DatabaseKeyedTable(super.tableName);

  @override
  DatabaseKeyedAccess<R, K> on(DatabaseSession session) {
    session._database._requireDeclared(this);
    return DatabaseKeyedAccess<R, K>._(session, this);
  }

  @override
  DatabaseField<Object?>? get _keyField => _key;

  late final DatabaseField<K> _key = _findKey();

  DatabaseField<K> _findKey() {
    final keys = columns.where((field) => field.isPrimary).toList();
    if (keys.length != 1) {
      throw StateError('$tableName is a keyed table and needs exactly one primary key column, but has ${keys.length}.');
    }
    final key = keys.single;
    if (key is! DatabaseField<K>) {
      throw StateError('$key holds a different type than the $K that $tableName declares as its key.');
    }
    return key;
  }

  @override
  DeclaredTable _declare() {
    _key;
    return super._declare();
  }
}
