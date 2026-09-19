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
  const DatabaseRows._(this._session, this._table, [this._filter, this._orders = const [], this._limit, this._offset]);

  final DatabaseSession _session;
  final DatabaseTable<R> _table;
  final DatabaseFilter? _filter;
  final List<DatabaseOrder> _orders;
  final int? _limit;
  final int? _offset;

  DatabaseRows<R> _copy({DatabaseFilter? filter, List<DatabaseOrder>? orders, int? limit, int? offset}) =>
      DatabaseRows<R>._(_session, _table, filter ?? _filter, orders ?? _orders, limit ?? _limit, offset ?? _offset);

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
  Future<List<R>> list() => _session._run((executor) async {
    final arguments = <DatabaseType>[];
    final where = _whereSql(_filter, arguments);
    final order = _orders.isEmpty ? '' : ' ORDER BY ${_orders.map(_renderOrder).join(', ')}';
    final limit = _limit ?? (_offset == null ? null : -1);
    final page = limit == null ? '' : ' LIMIT $limit${_offset == null ? '' : ' OFFSET $_offset'}';
    final rows = await executor.rawQuery(
      'SELECT ${_table._columnList} FROM ${_quotedIdentifier(_table.tableName)}$where$order$page',
      _toNativeArgs(arguments),
    );
    return [for (final row in rows) _table._fromRow(_fromNativeRow(row))];
  });

  /// The first row kept, or null when none is.
  Future<R?> first() async => (await _copy(limit: 1).list()).firstOrNull;

  /// How many rows are kept.
  ///
  /// Throws a [StateError] when a [limit] or an [offset] was set, which a
  /// count would silently ignore.
  Future<int> count() => _session._run((executor) async {
    _requireNoPage('count');
    final arguments = <DatabaseType>[];
    final where = _whereSql(_filter, arguments);
    final rows = await executor.rawQuery(
      'SELECT COUNT(*) AS n FROM ${_quotedIdentifier(_table.tableName)}$where',
      _toNativeArgs(arguments),
    );
    return _fromNative(rows.single['n']).asInt;
  });

  /// Whether at least one row is kept.
  ///
  /// Throws a [StateError] when a [limit] or an [offset] was set.
  Future<bool> exists() => _session._run((executor) async {
    _requireNoPage('exists');
    final arguments = <DatabaseType>[];
    final where = _whereSql(_filter, arguments);
    final rows = await executor.rawQuery(
      'SELECT EXISTS(SELECT 1 FROM ${_quotedIdentifier(_table.tableName)}$where) AS present',
      _toNativeArgs(arguments),
    );
    return _fromNative(rows.single['present']).asBoolean;
  });

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

  Future<int> _write(List<DatabaseAssignment> assignments) => _writeValues(_table._valuesOf(assignments));

  Future<int> _writeValues(Map<String, DatabaseType> values) => _session._run((executor) async {
    _requireNoPage('a write');
    if (values.isEmpty) throw StateError('A write on ${_table.tableName} needs at least one column to set.');
    final arguments = values.values.toList();
    final set = values.keys.map((name) => '${_quotedIdentifier(name)} = ?').join(', ');
    final where = _whereSql(_filter, arguments);
    return executor.rawUpdate('UPDATE ${_quotedIdentifier(_table.tableName)} SET $set$where', _toNativeArgs(arguments));
  });

  Future<int> _remove() => _session._run((executor) async {
    _requireNoPage('a delete');
    final arguments = <DatabaseType>[];
    final where = _whereSql(_filter, arguments);
    return executor.rawDelete('DELETE FROM ${_quotedIdentifier(_table.tableName)}$where', _toNativeArgs(arguments));
  });
}

/// A table read and written through one [DatabaseSession], opened by
/// [DatabaseTable.on]. Everything [DatabaseRows] reads and edits is here too,
/// over the whole table, and inserting is added.
base class DatabaseTableAccess<R extends Object> extends DatabaseRows<R> {
  const DatabaseTableAccess._(super.session, super.table) : super._();

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
    return _session._run((executor) async {
      final batch = executor.batch();
      for (final record in records) {
        final (sql, arguments) = _insertSql(_table.tableName, _table._rowOf(record, generateKey: true));
        batch.rawInsert(sql, arguments);
      }
      final rowIds = (await batch.commit()).cast<int>();
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
  const DatabaseKeyedAccess._(super.session, DatabaseKeyedTable<R, K> super.table) : super._();

  DatabaseKeyedTable<R, K> get _keyed => _table as DatabaseKeyedTable<R, K>;

  /// The record whose key is [key], or null when there is none.
  Future<R?> get(K key) => where(_keyed._key.isEqualTo(key)).first();

  /// Removes the row whose key is [key], and answers whether there was one.
  Future<bool> remove(K key) async => await where(_keyed._key.isEqualTo(key)).delete() > 0;

  /// Writes [record] over the row that holds its key, or inserts it when no
  /// row does, and answers the record the database now holds.
  ///
  /// The row is updated in place. It is never deleted and reinserted, so the
  /// rows of other tables that point at it are untouched. A record with no key
  /// yet is inserted, and the engine assigns one.
  Future<R> upsert(R record) => _session._atomically((session) async {
    final access = _keyed.on(session);
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
  });
}
