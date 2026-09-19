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

/// Where a table is read and written: either a [LocalDatabase] or the
/// [DatabaseTransaction] one of its transactions hands to your callback.
///
/// Both accept `todos.on(session)`, so a function that takes a
/// [DatabaseSession] runs the same way inside and outside a transaction.
sealed class DatabaseSession {
  DatabaseExecutor _executor();

  LocalDatabase get _database;

  Future<T> _atomically<T>(Future<T> Function(DatabaseSession session) action);

  Future<T> _run<T>(Future<T> Function(DatabaseExecutor executor) action) => _guarded(() => action(_executor()));
}

const String _rowIdColumn = '__rowid';

String _whereSql(DatabaseFilter? filter, List<DatabaseType> arguments) {
  if (filter == null) return '';
  final (clause, filterArguments) = _renderDatabaseFilter(filter);
  arguments.addAll(filterArguments);
  return ' WHERE $clause';
}

(String, List<Object?>?) _insertSql(String table, Map<String, DatabaseType> row) {
  final target = _quotedIdentifier(table);
  if (row.isEmpty) return ('INSERT INTO $target DEFAULT VALUES', null);
  final names = row.keys.map(_quotedIdentifier).join(', ');
  final placeholders = List.filled(row.length, '?').join(', ');
  return ('INSERT INTO $target ($names) VALUES ($placeholders)', _toNativeArgs(row.values.toList()));
}

/// The rows of one table, narrowed by a filter, an order and a page, read
/// through one [DatabaseSession]. Every method that narrows answers a new
/// value, so a half built query can be kept and extended.
///
/// ```dart
/// final open = await todos
///     .on(db)
///     .where(todos.done.isEqualTo(false) & todos.due.isNotNull())
///     .orderBy([todos.due.asc()])
///     .limit(20)
///     .list();
/// ```
///
/// A filter or an order built from a column of another table is refused, so
/// a column shared by name between two tables cannot be read from the wrong
/// one. Reading with no [orderBy] gives no promised order.
base class DatabaseRows<R extends Object> {
  const DatabaseRows._(
    this._session,
    this._table, [
    this._filter,
    this._orders = const [],
    this._limit,
    this._offset,
    this._scope = const _CurrentScope(),
  ]);

  final DatabaseSession _session;
  final DatabaseTable<R> _table;
  final DatabaseFilter? _filter;
  final List<DatabaseOrder> _orders;
  final int? _limit;
  final int? _offset;
  final _Scope _scope;

  DatabaseRows<R> _copy({DatabaseFilter? filter, List<DatabaseOrder>? orders, int? limit, int? offset}) =>
      DatabaseRows<R>._(
        _session,
        _table,
        filter ?? _filter,
        orders ?? _orders,
        limit ?? _limit,
        offset ?? _offset,
        _scope,
      );

  /// Whose rows this reaches, resolved now. Every operation reads it once,
  /// before it awaits anything, so it finishes on the tenant that was current
  /// when it started.
  _Reach _reach() => _scope.reach(_table);

  /// The filter every read and write of this table starts from: on an
  /// isolated table, the tenant condition comes first and no method of this
  /// class can leave it out.
  DatabaseFilter? _scopedFilter(_Reach reach) {
    if (_table.tunnel == Tunnel.shared) return _filter;
    final quoted = _quotedIdentifier(_tenantColumn);
    final DatabaseFilter? partition;
    if (!reach.isMany) {
      partition = _DatabaseFilterRaw('$quoted = ?', [DatabaseType.varchar(reach.tenant!)]);
    } else if (reach.only case final only?) {
      if (only.isEmpty) throw ArgumentError.value(only, 'only', 'cannot be empty');
      partition = _DatabaseFilterRaw('$quoted IN (${List.filled(only.length, '?').join(', ')})', [
        for (final tenant in only) DatabaseType.varchar(tenant),
      ]);
    } else {
      partition = null;
    }
    if (partition == null) return _filter;
    return _filter == null ? partition : partition & _filter;
  }

  /// Keeps only the rows [filter] matches. Calling it again keeps the rows
  /// both filters match, rather than replacing the first.
  ///
  /// Throws an [ArgumentError] when [filter] uses a column of another table.
  DatabaseRows<R> where(DatabaseFilter filter) {
    final foreign = filter._tables.difference({_table.tableName});
    if (foreign.isNotEmpty) {
      throw ArgumentError.value(
        filter,
        'filter',
        'It reads ${foreign.join(', ')} but this query reads ${_table.tableName}.',
      );
    }
    return _copy(filter: _filter == null ? filter : _filter & filter);
  }

  /// Sorts the rows by [orders], the first deciding and each later one
  /// breaking the ties of the one before it.
  DatabaseRows<R> orderBy(List<DatabaseOrder> orders) => _copy(orders: orders);

  /// Reads at most [count] rows.
  ///
  /// Throws a [RangeError] when [count] is negative, which SQLite would read
  /// as no limit at all.
  DatabaseRows<R> limit(int count) => _copy(limit: RangeError.checkNotNegative(count, 'count'));

  /// Skips the first [count] matching rows.
  ///
  /// Throws a [RangeError] when [count] is negative.
  DatabaseRows<R> offset(int count) => _copy(offset: RangeError.checkNotNegative(count, 'count'));

  /// Every row kept, as records.
  Future<List<R>> list() async => [for (final row in await _selectRows()) _table._fromRow(row)];

  Future<List<DatabaseRow>> _selectRows({bool withTenant = false}) {
    final reach = _reach();
    return _session._run((executor) async {
      final arguments = <DatabaseType>[];
      final where = _whereSql(_scopedFilter(reach), arguments);
      final tieBreak = reach.isMany && _orders.isNotEmpty ? ', ${_quotedIdentifier(_tenantColumn)}' : '';
      final order = _orders.isEmpty ? '' : ' ORDER BY ${_orders.map(_renderOrder).join(', ')}$tieBreak';
      final limit = _limit ?? (_offset == null ? null : -1);
      final page = limit == null ? '' : ' LIMIT $limit${_offset == null ? '' : ' OFFSET $_offset'}';
      final tenant = withTenant && _table.tunnel == Tunnel.isolated ? ', ${_quotedIdentifier(_tenantColumn)}' : '';
      final rows = await executor.rawQuery(
        'SELECT ${_table._columnList}$tenant FROM ${_quotedIdentifier(_table.tableName)}$where$order$page',
        _toNativeArgs(arguments),
      );
      return rows.map(_fromNativeRow).toList();
    });
  }

  /// The first row kept, or null when none is.
  Future<R?> first() async => (await _copy(limit: 1).list()).firstOrNull;

  /// Every row kept, as records, now and again after each write to this table
  /// that changes what is kept.
  ///
  /// ```dart
  /// todos.on(db).where(todos.done.isEqualTo(false)).orderBy([todos.due.asc()]).watch().listen(show);
  /// ```
  ///
  /// The first event is the current rows, and one more follows each write to
  /// the table — an insert, an update, a delete, a batch, a committed
  /// transaction — after which the rows kept differ from the last ones sent. A
  /// write that leaves them as they were sends nothing. Nothing is read until
  /// the stream is listened to, and it stops when the listener cancels.
  ///
  /// Throws a [StateError] on a session that is a [DatabaseTransaction]: it
  /// ends before anything could change, so a stream over it would never send a
  /// second event.
  Stream<List<R>> watch() => _watchRows().map((rows) => [for (final row in rows) _table._fromRow(row)]);

  /// The first row kept, or null when none is, now and again after each write
  /// that changes it. See [watch].
  Stream<R?> watchFirst() => _copy(limit: 1).watch().map((records) => records.firstOrNull);

  /// How many rows are kept, now and again after each write that changes the
  /// number. See [watch].
  ///
  /// Throws a [StateError] when a [limit] or an [offset] was set, as [count]
  /// does.
  Stream<int> watchCount() {
    _requireNoPage('watchCount');
    return _watchTable<int>(
      _watchedDatabase(),
      _table.tableName,
      count,
      (previous, current) => previous == current,
      followsTenant: _followsTenant,
    );
  }

  Stream<List<DatabaseRow>> _watchRows() => _watchTable<List<DatabaseRow>>(
    _watchedDatabase(),
    _table.tableName,
    _selectRows,
    _sameRows,
    followsTenant: _followsTenant,
  );

  /// Whether what this watches changes with [Tenant.current].
  bool get _followsTenant => _scope is _CurrentScope && _table.tunnel == Tunnel.isolated;

  LocalDatabase _watchedDatabase() {
    if (_session is DatabaseTransaction) {
      throw StateError(
        'watch on ${_table.tableName} needs a LocalDatabase: a transaction ends before it could change.',
      );
    }
    return _session._database;
  }

  /// How many rows are kept.
  ///
  /// Throws a [StateError] when a [limit] or an [offset] was set, which a
  /// count would silently ignore.
  Future<int> count() {
    final reach = _reach();
    return _session._run((executor) async {
      _requireNoPage('count');
      final arguments = <DatabaseType>[];
      final where = _whereSql(_scopedFilter(reach), arguments);
      final rows = await executor.rawQuery(
        'SELECT COUNT(*) AS n FROM ${_quotedIdentifier(_table.tableName)}$where',
        _toNativeArgs(arguments),
      );
      return _fromNative(rows.single['n']).asInt;
    });
  }

  /// Whether at least one row is kept.
  ///
  /// Throws a [StateError] when a [limit] or an [offset] was set.
  Future<bool> exists() {
    final reach = _reach();
    return _session._run((executor) async {
      _requireNoPage('exists');
      final arguments = <DatabaseType>[];
      final where = _whereSql(_scopedFilter(reach), arguments);
      final rows = await executor.rawQuery(
        'SELECT EXISTS(SELECT 1 FROM ${_quotedIdentifier(_table.tableName)}$where) AS present',
        _toNativeArgs(arguments),
      );
      return _fromNative(rows.single['present']).asBoolean;
    });
  }

  /// Writes [assignments] over every row kept, and answers how many changed.
  ///
  /// Throws a [StateError] when no [where] narrowed the rows, which would
  /// rewrite the whole table: say so with [updateAll]. Also throws when a
  /// [limit] or an [offset] was set, which an update would ignore.
  Future<int> update(List<DatabaseAssignment> assignments) async {
    if (_filter == null) {
      throw StateError('update on ${_table.tableName} has no where. Use updateAll to rewrite every row.');
    }
    return _write(assignments);
  }

  /// Writes [assignments] over every row of the table.
  ///
  /// Throws a [StateError] when a [where] narrowed the rows, which [update]
  /// is for.
  Future<int> updateAll(List<DatabaseAssignment> assignments) async {
    if (_filter != null) throw StateError('updateAll on ${_table.tableName} has a where. Use update.');
    return _write(assignments);
  }

  /// Removes every row kept, and answers how many were removed.
  ///
  /// Throws a [StateError] when no [where] narrowed the rows, which would
  /// empty the table: say so with [deleteAll]. Also throws when a [limit] or
  /// an [offset] was set, which a delete would ignore.
  Future<int> delete() async {
    if (_filter == null) {
      throw StateError('delete on ${_table.tableName} has no where. Use deleteAll to remove every row.');
    }
    return _remove();
  }

  /// Removes every row of the table.
  ///
  /// Throws a [StateError] when a [where] narrowed the rows, which [delete]
  /// is for.
  Future<int> deleteAll() async {
    if (_filter != null) throw StateError('deleteAll on ${_table.tableName} has a where. Use delete.');
    return _remove();
  }

  void _requireNoPage(String method) {
    if (_limit != null || _offset != null) {
      throw StateError('$method on ${_table.tableName} ignores limit and offset, so they must not be set.');
    }
  }

  Future<int> _write(List<DatabaseAssignment> assignments) {
    final update = _table._updateOf(assignments);
    return _writeClauses(update.clauses, update.arguments);
  }

  Future<int> _writeValues(Map<String, DatabaseType> values) =>
      _writeClauses([for (final name in values.keys) '${_quotedIdentifier(name)} = ?'], values.values.toList());

  Future<int> _writeClauses(List<String> clauses, List<DatabaseType> values) {
    final reach = _reach();
    return _session._run((executor) async {
      _requireNoPage('a write');
      if (clauses.isEmpty) throw StateError('A write on ${_table.tableName} needs at least one column to set.');
      final arguments = [...values];
      final set = clauses.join(', ');
      final where = _whereSql(_scopedFilter(reach), arguments);
      final changed = await executor.rawUpdate(
        'UPDATE ${_quotedIdentifier(_table.tableName)} SET $set$where',
        _toNativeArgs(arguments),
      );
      if (changed > 0) _session._database._notifyWrite({_table.tableName});
      return changed;
    });
  }

  Future<int> _remove() {
    final reach = _reach();
    return _session._run((executor) async {
      _requireNoPage('a delete');
      final arguments = <DatabaseType>[];
      final where = _whereSql(_scopedFilter(reach), arguments);
      final removed = await executor.rawDelete(
        'DELETE FROM ${_quotedIdentifier(_table.tableName)}$where',
        _toNativeArgs(arguments),
      );
      if (removed > 0) _session._database._notifyWrite({_table.tableName});
      return removed;
    });
  }
}

/// A table read and written through one [DatabaseSession], opened by
/// [DatabaseTable.on]. Everything [DatabaseRows] reads and edits is here too,
/// over the whole table, and inserting is added.
base class DatabaseTableAccess<R extends Object> extends DatabaseRows<R> {
  const DatabaseTableAccess._(DatabaseSession session, DatabaseTable<R> table, [_Scope scope = const _CurrentScope()])
    : super._(session, table, null, const [], null, null, scope);

  /// Inserts [record] and answers the record the database now holds, so the
  /// key it was given and any default it took are already in it.
  ///
  /// Throws a [DatabaseUniqueConstraintError] when a unique column or the key
  /// collides with a row already there. Nothing is replaced silently.
  Future<R> insert(R record) async => (await insertAll([record])).single;

  /// Inserts every record of [records], in order, as one unit: either every
  /// row lands or none does. Answers the records the database now holds.
  Future<List<R>> insertAll(List<R> records) {
    if (records.isEmpty) return Future.value(const []);
    final tenant = _table.tunnel == Tunnel.isolated ? _reach().tenant! : null;
    return _session._run((executor) async {
      final batch = executor.batch();
      for (final record in records) {
        final row = _table._rowOf(record, generateKey: true);
        if (tenant != null) row[_tenantColumn] = DatabaseType.varchar(tenant);
        final (sql, arguments) = _insertSql(_table.tableName, row);
        batch.rawInsert(sql, arguments);
      }
      final rowIds = (await batch.commit()).cast<int>();
      _session._database._notifyWrite({_table.tableName});
      return _readByRowId(executor, rowIds);
    });
  }

  Future<List<R>> _readByRowId(DatabaseExecutor executor, List<int> rowIds) async {
    final found = <int, R>{};
    for (var start = 0; start < rowIds.length; start += 500) {
      final chunk = rowIds.sublist(start, start + 500 > rowIds.length ? rowIds.length : start + 500);
      final rows = await executor.rawQuery(
        'SELECT ${_table._columnList}, rowid AS $_rowIdColumn FROM ${_quotedIdentifier(_table.tableName)} '
        'WHERE rowid IN (${List.filled(chunk.length, '?').join(', ')})',
        chunk,
      );
      for (final row in rows) {
        found[row[_rowIdColumn]! as int] = _table._fromRow(_fromNativeRow(row));
      }
    }
    return [for (final rowId in rowIds) found[rowId] as R];
  }
}

/// A keyed table read and written through one [DatabaseSession], opened by
/// [DatabaseKeyedTable.on]. It adds what a key makes possible: reading, writing
/// and removing one row by its key.
final class DatabaseKeyedAccess<R extends Object, K extends Object> extends DatabaseTableAccess<R> {
  const DatabaseKeyedAccess._(super.session, DatabaseKeyedTable<R, K> super.table, [super.scope]) : super._();

  DatabaseKeyedTable<R, K> get _keyed => _table as DatabaseKeyedTable<R, K>;

  /// The record whose key is [key], or null when there is none.
  Future<R?> get(K key) => where(_keyed._key.isEqualTo(key)).first();

  /// The record whose key is [key], now and again after each write that
  /// changes it, or null while there is none. See [DatabaseRows.watch].
  Stream<R?> watchOne(K key) => where(_keyed._key.isEqualTo(key)).watchFirst();

  /// Removes the row whose key is [key], and answers whether there was one.
  Future<bool> remove(K key) async => await where(_keyed._key.isEqualTo(key)).delete() > 0;

  /// Writes [record] over the row that holds its key, or inserts it when no
  /// row does, and answers the record the database now holds.
  ///
  /// The row is updated in place. It is never deleted and reinserted, so the
  /// rows of other tables that point at it are untouched. A record with no key
  /// yet is inserted, and the engine assigns one.
  Future<R> upsert(R record) {
    // Held from here: the whole upsert runs on the tenant it started on.
    final scope = _table.tunnel == Tunnel.isolated ? _PinnedScope(_reach().tenant!) : const _CurrentScope();
    return _session._atomically((session) => _upsertOn(DatabaseKeyedAccess<R, K>._(session, _keyed, scope), record));
  }

  Future<R> _upsertOn(DatabaseKeyedAccess<R, K> access, R record) async {
    final row = _table._rowOf(record, generateKey: false);
    final key = _keyed._key;
    final keyValue = row.remove(key.name);
    if (keyValue == null) return access.insert(record);
    final sameKey = _DatabaseFilterOfTable(
      _DatabaseFilterComparison(key.name, _Comparison.equal, keyValue),
      _table.tableName,
    );
    final changed = row.isEmpty
        ? (await access.where(sameKey).exists() ? 1 : 0)
        : await access.where(sameKey)._writeValues(row);
    if (changed == 0) return access.insert(record);
    return (await access.where(sameKey).first())!;
  }
}

/// The rows of one table across every tenant: the whole-database mechanism,
/// opened by [DatabaseTable.onWholeDatabase].
///
/// It is not the tenant mechanism with a wider view. [DatabaseTable.on] never
/// reaches another tenant's rows, whatever is called on what it returns; this
/// is a separate entry point, picked on purpose, that reaches all of them —
/// for a support tool, a backup, a migration, anything that is about the
/// whole database rather than about one account. It reads, and it edits or
/// removes the rows a filter keeps, wherever they belong; it inserts nothing,
/// since a new row belongs to one tenant, which is [DatabaseTable.on]'s to say.
///
/// A shared table has no tenants, so here it is simply all of its rows.
final class DatabaseWholeRows<R extends Object> extends DatabaseRows<R> {
  const DatabaseWholeRows._(
    super.session,
    super.table, [
    super.filter,
    super.orders,
    super.limit,
    super.offset,
    super.scope = const _AllScope(null),
  ]) : super._();

  @override
  DatabaseWholeRows<R> _copy({DatabaseFilter? filter, List<DatabaseOrder>? orders, int? limit, int? offset}) =>
      DatabaseWholeRows<R>._(
        _session,
        _table,
        filter ?? _filter,
        orders ?? _orders,
        limit ?? _limit,
        offset ?? _offset,
        _scope,
      );

  @override
  DatabaseWholeRows<R> where(DatabaseFilter filter) => super.where(filter) as DatabaseWholeRows<R>;

  @override
  DatabaseWholeRows<R> orderBy(List<DatabaseOrder> orders) => super.orderBy(orders) as DatabaseWholeRows<R>;

  @override
  DatabaseWholeRows<R> limit(int count) => super.limit(count) as DatabaseWholeRows<R>;

  @override
  DatabaseWholeRows<R> offset(int count) => super.offset(count) as DatabaseWholeRows<R>;

  /// Only the rows of [tenants]. Throws an [ArgumentError] when it is empty.
  DatabaseWholeRows<R> ofTenants(Iterable<String> tenants) {
    final only = tenants.toSet();
    if (only.isEmpty) throw ArgumentError.value(tenants, 'tenants', 'cannot be empty');
    only.forEach(_checkTenantId);
    return DatabaseWholeRows<R>._(_session, _table, _filter, _orders, _limit, _offset, _AllScope(only));
  }

  /// Every row kept, with the tenant each belongs to — `null` for the
  /// anonymous rows and for a shared table's — since one key can now come back
  /// once per tenant.
  Future<List<({String? tenant, R record})>> listWithTenants() async {
    final rows = await _selectRows(withTenant: true);
    return [
      for (final row in rows)
        (tenant: _table.tunnel == Tunnel.isolated ? _tenantOf(row) : null, record: _table._fromRow(row)),
    ];
  }

  String? _tenantOf(DatabaseRow row) {
    final tenant = row[_tenantColumn]!.asString;
    return tenant.isEmpty ? null : tenant;
  }
}
