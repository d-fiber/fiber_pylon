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

part of '../database.dart';

final ColumnCodec<int> _integerCodec = ColumnCodec<int>(
  storage: ColumnType.integer,
  encode: Value.integer,
  decode: (stored) => stored.asInt,
);

final ColumnCodec<double> _realCodec = ColumnCodec<double>(
  storage: ColumnType.real,
  encode: Value.real,
  decode: (stored) => stored.asDouble,
);

final ColumnCodec<String> _textCodec = ColumnCodec<String>(
  storage: ColumnType.text,
  encode: Value.varchar,
  decode: (stored) => stored.asString,
);

final ColumnCodec<Uint8List> _blobCodec = ColumnCodec<Uint8List>(
  storage: ColumnType.blob,
  encode: Value.blob,
  decode: (stored) => stored.asBytes,
);

final ColumnCodec<bool> _booleanCodec = ColumnCodec<bool>(
  storage: ColumnType.integer,
  encode: Value.boolean,
  decode: (stored) => stored.asBoolean,
);

final ColumnCodec<DateTime> _timestampCodec = ColumnCodec<DateTime>(
  storage: ColumnType.integer,
  encode: (value) => Value.timestamp(value.millisecondsSinceEpoch),
  decode: (stored) => stored.asDateTime,
);

final ColumnCodec<Date> _dateCodec = ColumnCodec<Date>(
  storage: ColumnType.integer,
  encode: Value.date,
  decode: (stored) => stored.asDate,
);

final ColumnCodec<Time> _timeCodec = ColumnCodec<Time>(
  storage: ColumnType.text,
  encode: Value.time,
  decode: (stored) => stored.asTime,
);

final ColumnCodec<UuidValue> _uuidCodec = ColumnCodec<UuidValue>(
  storage: ColumnType.text,
  encode: Value.uuid,
  decode: (stored) => stored.asUuid,
);

/// The columns of one table, opened through [TypedTable.column].
///
/// Each method takes the name the column has in the database, and answers a
/// [Field] typed with the Dart type that column holds. A column refuses NULL
/// until [Field.nullable] says otherwise.
final class Columns {
  const Columns._(this._table, this._isolated);

  /// The name of the table the columns belong to.
  final String _table;

  /// Whether that table is [Tunnel.isolated].
  final bool _isolated;

  /// An integer primary key the database numbers itself, and never numbers
  /// twice: a deleted row's key is not handed out again.
  KeyField<int> key([String name = 'id']) => KeyField<int>._(
    _table,
    name,
    _FieldDefinition(codec: _integerCodec._erased, isPrimary: true, isAutoincrement: true, isolated: _isolated),
  );

  /// A UUID primary key. The engine generates a random one on insert when a
  /// record does not carry one yet.
  KeyField<UuidValue> uuidKey([String name = 'id']) => KeyField<UuidValue>._(
    _table,
    name,
    _FieldDefinition(codec: _uuidCodec._erased, isPrimary: true, generator: Value.randomUuid, isolated: _isolated),
  );

  /// A whole number of up to 64 bits.
  Field<int> integer(String name) => custom(name, _integerCodec);

  /// A floating point number.
  Field<double> real(String name) => custom(name, _realCodec);

  /// Text.
  Field<String> text(String name) => custom(name, _textCodec);

  /// Raw bytes.
  Field<Uint8List> blob(String name) => custom(name, _blobCodec);

  /// A boolean.
  Field<bool> boolean(String name) => custom(name, _booleanCodec);

  /// An instant, kept to the millisecond and read back as a UTC [DateTime].
  Field<DateTime> timestamp(String name) => custom(name, _timestampCodec);

  /// A calendar date with no time of day, the same on every device.
  Field<Date> date(String name) => custom(name, _dateCodec);

  /// A time of day with no calendar date.
  Field<Time> time(String name) => custom(name, _timeCodec);

  /// A UUID.
  Field<UuidValue> uuid(String name) => custom(name, _uuidCodec);

  /// One member of [values], stored by name, so that reordering the enum never
  /// changes what a stored row means.
  Field<E> enumeration<E extends Enum>(String name, List<E> values) => custom(
    name,
    ColumnCodec<E>(storage: ColumnType.text, encode: Value.enum_, decode: (stored) => stored.asEnum(values)),
  );

  /// A list of native JSON values.
  Field<List<T>> list<T>(String name) => custom(
    name,
    ColumnCodec<List<T>>(storage: ColumnType.text, encode: Value.list, decode: (stored) => stored.asList<T>()),
  );

  /// A value of your own type, converted through [json].
  Field<T> json<T extends Object>(String name, Json<T> json) =>
      custom(name, ColumnCodec<T>(storage: ColumnType.text, encode: json.encode, decode: json.decode));

  /// A value of your own type, stored the way [codec] says.
  Field<V> custom<V extends Object>(String name, ColumnCodec<V> codec) =>
      Field<V>._(_table, name, _FieldDefinition(codec: codec._erased, isolated: _isolated));
}

/// One row of a table as a query read it, handed to [TypedTable.read].
///
/// Calling it with a column answers that column's value already decoded to
/// the Dart type of the column: `row(title)` is a `String`, `row(due)` is a
/// `Date?` when `due` accepts NULL.
final class Reader {
  const Reader._(this._table, this._row);

  /// The name of the table this row was read from.
  final String _table;

  /// The columns this row was read with, as the database returned them.
  final RawRow _row;

  /// The value [field] holds in this row.
  ///
  /// Throws a [StateError] when [field] belongs to another table, or when it
  /// holds NULL although it was not declared nullable.
  V call<V>(Field<V> field) {
    if (field.table != _table) throw StateError('$field was read through a row of $_table.');
    final stored = _row[field.name];
    if (stored == null) throw StateError('$field is not among the columns this row was read with.');
    return field._decode(stored);
  }
}

/// A table of the database and the record type [R] its rows map to.
///
/// A project declares one subclass per table, and that is all the schema and
/// the mapping it writes.
///
/// ```dart
/// final class Todos extends KeyedTable<Todo, int> {
///   Todos() : super('todos');
///
///   late final id = column.key();
///   late final title = column.text('title');
///   late final done = column.boolean('done').defaultsTo(false);
///   late final due = column.date('due').nullable();
///
///   @override
///   List<Field<Object?>> get columns => [id, title, done, due];
///
///   @override
///   Todo read(Reader row) => Todo(id: row(id), title: row(title), done: row(done), due: row(due));
///
///   @override
///   List<Assignment> write(Todo todo) =>
///       [id.toOrGenerate(todo.id), title.to(todo.title), done.to(todo.done), due.to(todo.due)];
/// }
///
/// final todos = Todos();
/// ```
///
/// Declare the table once, at top level, hand it to [LocalDatabase.declare],
/// and read and write it through [on]. The names [tableName], [column],
/// [columns], [primaryKey], [uniques], [indexes], [read], [write], [on] and
/// [declaration] belong to this class, so a column cannot be a field called
/// one of them.
abstract class TypedTable<R extends Object> {
  /// A table called [tableName] in the database.
  TypedTable(this.tableName);

  /// The name of this table in the database.
  final String tableName;

  /// Opens the columns of this table. Each `late final` field of the subclass
  /// is one call.
  late final Columns column = Columns._(tableName, tunnel == Tunnel.isolated);

  /// Whose rows this table holds: [Tunnel.shared], one copy for everyone (the
  /// default), or [Tunnel.isolated], where every [Tenant] has rows of its own.
  ///
  /// An isolated table gains a hidden column that holds the tenant of each row,
  /// and the engine adds it to every read and write, so no query can reach
  /// another tenant's rows by leaving a condition out. Its unique columns, and
  /// its key unless the database numbers it ([Columns.key]), are unique per
  /// tenant, not across them; an auto-numbered key is unique across all of them.
  /// An index and a foreign key to another isolated table are per tenant too.
  /// Changing the tunnel of a table that already holds rows needs a migration.
  Tunnel get tunnel => Tunnel.shared;

  /// Every column of this table, in the order they are created.
  ///
  /// A column missing from here is not created. Writing it, or reading it
  /// through a [Reader], throws a [StateError] naming it, and a filter on it
  /// fails when the query runs.
  List<Field<Object?>> get columns;

  /// The columns that together make the primary key, for a table with no
  /// single key column, such as one that links two others.
  List<Field<Object?>> get primaryKey => const [];

  /// Each list of columns that must not repeat together across two rows.
  List<List<Field<Object?>>> get uniques => const [];

  /// Each list of columns worth an index, for a column filtered or ordered on
  /// often. A column that references another table is not indexed unless it
  /// is listed here.
  List<List<Field<Object?>>> get indexes => const [];

  /// Builds a record from one row.
  R read(Reader row);

  /// The columns of [record] this table writes, each paired with its value.
  List<Assignment> write(R record);

  /// This table read and written through [session], a [LocalDatabase] or the
  /// [TransactionScope] of one of its transactions.
  ///
  /// Throws a [StateError] when the database was declared with tables and this
  /// one is not among them.
  TableAccess<R> on(Connection session) {
    session._database._requireDeclared(this);
    return TableAccess<R>._(session, this);
  }

  /// This table across every tenant, read and written through [session]: the
  /// whole-database mechanism, which is a separate entry point from [on], not a
  /// wider view of it. See [WholeRows].
  ///
  /// Reaching the whole database takes the app's [Fingerprint], which must be
  /// the one the database was opened with. Throws a [StateError] otherwise, and
  /// as [on] does when this table is not declared.
  WholeRows<R> onWholeDatabase(Connection session, Fingerprint fingerprint) {
    session._database._requireDeclared(this);
    session._database._requireFingerprint(fingerprint);
    return WholeRows<R>._(session, this);
  }

  /// The schema this table declares.
  ///
  /// Throws a [StateError] when the declaration is inconsistent: a column listed
  /// twice or owned by another table, a column called `__tenant` on an isolated
  /// table, or a foreign key from a shared table to an isolated one.
  late final DeclaredTable declaration = _declare();

  Field<Object?>? get _keyField => null;

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

  /// The schema of this table as an isolated one.
  ///
  /// A hidden tenant column joins the key, every unique constraint, every index
  /// and every foreign key to another isolated table, so that two tenants never
  /// collide and a row never points at another tenant's. An auto-numbered key
  /// stays alone as the primary key, since SQLite only numbers a single-column
  /// one, and the tenant joins a unique constraint that foreign keys point at.
  DeclaredTable _declareIsolated(Set<String> names) {
    if (names.contains(_tenantColumn)) {
      throw StateError('$tableName declares a column called $_tenantColumn, which an isolated table reserves.');
    }
    final keyColumns = [
      for (final field in columns)
        if (field.isPrimary) field,
    ];
    final autoKey = keyColumns.any((field) => field._definition.isAutoincrement);
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
      final map = <String, ColumnBuilder<dynamic, Value>>{};
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

  TableForeignKeyBuilder _tenantForeignKey(TableForeignKeyFactory factory, Field<Object?> field) {
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

  void _requireOwned(Field<Object?> field) {
    if (field.table != tableName || !columns.contains(field)) {
      throw StateError('$field is not listed in the columns of $tableName.');
    }
  }

  /// Whether [a] and [b] write the same value to every column, which is what
  /// tells a record that changed from one that did not.
  bool isSameRecord(R a, R b) {
    final left = _valuesOf(write(a));
    final right = _valuesOf(write(b));
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) || right[entry.key] != entry.value) return false;
    }
    return true;
  }

  Map<String, Value> _rowOf(R record, {required bool generateKey}) {
    final row = _valuesOf(write(record));
    final key = _keyField;
    if (generateKey && key is KeyField<Object> && !row.containsKey(key.name)) {
      final generated = key._generate();
      if (generated != null) row[key.name] = generated;
    }
    return row;
  }

  Map<String, Value> _valuesOf(List<Assignment> assignments) {
    final row = <String, Value>{};
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
  ({List<String> clauses, List<Value> arguments}) _updateOf(List<Assignment> assignments) {
    final written = <String>{};
    final clauses = <String>[];
    final arguments = <Value>[];
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

  R _fromRow(RawRow row) => read(Reader._(tableName, row));
}

/// A [TypedTable] whose rows are told apart by one primary key column of
/// the Dart type [K], which unlocks reading a row by its key, upserting a
/// record and deleting a row by its key.
///
/// The key is the one column of [columns] opened as a key, through
/// [Columns.key], [Columns.uuidKey] or [Field.primaryKey], and its Dart type
/// must be [K]. Both are checked when [declaration] is first read, which is
/// when the table is declared on a database.
abstract class KeyedTable<R extends Object, K extends Object> extends TypedTable<R> {
  /// A keyed table called [tableName] in the database.
  KeyedTable(super.tableName);

  @override
  KeyedAccess<R, K> on(Connection session) {
    session._database._requireDeclared(this);
    return KeyedAccess<R, K>._(session, this);
  }

  @override
  Field<Object?>? get _keyField => _key;

  /// The column that is the key of this table, so a filter can name it.
  Field<K> get keyField => _key;

  /// The key [record] carries, or null when it carries none yet, which is a
  /// record whose key the engine will assign on insert.
  K? keyOf(R record) {
    final value = _rowOf(record, generateKey: false)[_key.name];
    return value == null ? null : _key._decode(value) as K?;
  }

  /// This table as [session] reaches it, on [tenant] whichever tenant is
  /// current, with `null` meaning the anonymous rows.
  ///
  /// It is how an operation that spans several calls, a batch or a transaction,
  /// keeps to the tenant it started on. A shared table has no tenants, so it
  /// ignores [tenant].
  ///
  /// Not for a project: the tenant mechanism never names a tenant. Only the
  /// package holds one, and only the one that was current when it began.
  @internal
  KeyedAccess<R, K> onHeldTenant(Connection session, String? tenant) {
    session._database._requireDeclared(this);
    return KeyedAccess<R, K>._(
      session,
      this,
      tunnel == Tunnel.isolated ? _PinnedScope(tenant ?? '') : const _CurrentScope(),
    );
  }

  late final Field<K> _key = _findKey();

  Field<K> _findKey() {
    final keys = columns.where((field) => field.isPrimary).toList();
    if (keys.length != 1) {
      throw StateError('$tableName is a keyed table and needs exactly one primary key column, but has ${keys.length}.');
    }
    final key = keys.single;
    if (key is! Field<K>) {
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
