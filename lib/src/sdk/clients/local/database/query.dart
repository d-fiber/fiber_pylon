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

final class _Order {
  const _Order(this.field, {required this.descending});

  final Field<Object> field;
  final bool descending;
}

final class _Cursor {
  const _Cursor(this.fields, this.values, {required this.inclusive});

  final List<Field<Object>> fields;
  final List<Object> values;
  final bool inclusive;
}

final class _QuerySpec {
  const _QuerySpec({
    this.filters = const [],
    this.orders = const [],
    this.limit,
    this.limitToLast = false,
    this.start,
    this.end,
  });

  final List<Filter> filters;
  final List<_Order> orders;
  final int? limit;
  final bool limitToLast;
  final _Cursor? start;
  final _Cursor? end;

  _QuerySpec copyWith({
    List<Filter>? filters,
    List<_Order>? orders,
    int? limit,
    bool? limitToLast,
    _Cursor? start,
    _Cursor? end,
  }) => _QuerySpec(
    filters: filters ?? this.filters,
    orders: orders ?? this.orders,
    limit: limit ?? this.limit,
    limitToLast: limitToLast ?? this.limitToLast,
    start: start ?? this.start,
    end: end ?? this.end,
  );
}

/// A question asked of one [Collection]: which documents, in which order, how
/// many. Immutable — every method below answers a new [Query] that adds one
/// more constraint to this one.
///
/// ```dart
/// final page = await users
///     .where((w) => w(User.age_).isGreaterThanOrEqualTo(18))
///     .orderBy((o) => [o.asc(User.name_)])
///     .limit(20)
///     .get();
/// ```
///
/// Two departures from Firestore, both because this runs on SQLite: there is
/// no rule against ordering or filtering on several fields (nothing needs an
/// index built first, though [Collection.indexes] makes a big collection
/// fast), and a document that lacks a field it is ordered by is left out,
/// `null` included.
class Query<T extends Model> {
  const Query._(this._origin, this._spec, this._scope);

  final Collection<T>? _origin;
  final _QuerySpec _spec;
  final _Scope _scope;

  Collection<T> get _collection => _origin ?? this as Collection<T>;

  Query<T> _with(_QuerySpec spec) => Query._(_collection, spec, _scope);

  /// The partitions this query reaches, resolved now: read once when an
  /// operation starts, and held for its whole length.
  _Reach _reach() => _scope.reach(_collection);

  /// This query as [tenant] sees it, whichever tenant is current.
  ///
  /// Throws a [StateError] on a [Tunnel.shared] collection, which has no
  /// tenants.
  Query<T> inTenant(String tenant) {
    _checkTenantId(tenant);
    _requireIsolated(_collection, 'inTenant');
    return Query._(_collection, _spec, _PinnedScope(tenant));
  }

  /// This query over the documents of every tenant at once — or only of
  /// [only] — for reading across accounts on purpose.
  ///
  /// The same id can now come back once per tenant: [DocumentSnapshot.tenant]
  /// says whose each document is, and its reference writes to that tenant.
  /// Results are ordered by the query's own order, ties by id and then by
  /// tenant. Cursors are not available across tenants. Throws a [StateError]
  /// on a [Tunnel.shared] collection.
  Query<T> acrossTenants({Iterable<String>? only}) {
    only?.forEach(_checkTenantId);
    _requireIsolated(_collection, 'acrossTenants');
    return Query._(_collection, _spec, _AllScope(only?.toSet()));
  }

  /// Keeps the documents [build] matches, composed from a [FilterBuilder].
  /// Every condition must hold, and so must those of every earlier [where].
  ///
  /// ```dart
  /// users.where((w) => w(User.age_).isGreaterThanOrEqualTo(18))
  /// ```
  ///
  /// The value each condition takes is of the type its field holds, so a
  /// mismatch does not compile, and no field is ever named by a string.
  Query<T> where(Filter Function(FilterBuilder w) build) {
    final filter = build(const FilterBuilder._());
    filter._compile(); // fails here, at the call, rather than when the query runs
    return _with(_spec.copyWith(filters: [..._spec.filters, filter]));
  }

  /// Sorts by the orders [build] returns, composed from an [OrderBuilder],
  /// after any earlier [orderBy]. Ties fall back to the document id.
  ///
  /// ```dart
  /// users.orderBy((o) => [o.asc(User.city_), o.desc(User.age_)])
  /// ```
  Query<T> orderBy(List<DocumentOrder> Function(OrderBuilder o) build) {
    final orders = build(const OrderBuilder._());
    if (orders.isEmpty) throw ArgumentError.value(orders, 'orders', 'cannot be empty');
    for (final order in orders) {
      _fieldExpression(order._field);
    }
    return _with(
      _spec.copyWith(
        orders: [
          ..._spec.orders,
          for (final order in orders) _Order(order._field, descending: order._order == SortOrder.desc),
        ],
      ),
    );
  }

  /// Keeps the first [limit] documents.
  Query<T> limit(int limit) {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be positive');
    }
    return _with(_spec.copyWith(limit: limit, limitToLast: false));
  }

  /// Keeps the last [limit] documents, still in the query's own order.
  ///
  /// Needs an [orderBy]: without one there is no telling which are last.
  Query<T> limitToLast(int limit) {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be positive');
    }
    return _with(_spec.copyWith(limit: limit, limitToLast: true));
  }

  /// Starts at the document whose [orderBy] fields equal the values [build]
  /// returns, included.
  ///
  /// [build] gives one value per field the query is ordered by, in that order
  /// (the document id, [Field.documentId], comes last when not ordered on
  /// explicitly), each of its field's own type:
  ///
  /// ```dart
  /// users.orderBy((o) => [o.asc(User.age_)]).startAt((c) => [c(User.age_).at(28)])
  /// ```
  ///
  /// Throws a [StateError] when a value's field is not the one the query is
  /// ordered by at that position.
  Query<T> startAt(List<CursorValue> Function(CursorBuilder c) build) =>
      _with(_spec.copyWith(start: _cursor(build, inclusive: true)));

  /// Starts right after the document [startAt] describes.
  Query<T> startAfter(List<CursorValue> Function(CursorBuilder c) build) =>
      _with(_spec.copyWith(start: _cursor(build, inclusive: false)));

  /// Ends at the document [startAt] describes, included.
  Query<T> endAt(List<CursorValue> Function(CursorBuilder c) build) =>
      _with(_spec.copyWith(end: _cursor(build, inclusive: true)));

  /// Ends right before the document [startAt] describes.
  Query<T> endBefore(List<CursorValue> Function(CursorBuilder c) build) =>
      _with(_spec.copyWith(end: _cursor(build, inclusive: false)));

  _Cursor _cursor(List<CursorValue> Function(CursorBuilder c) build, {required bool inclusive}) {
    final values = build(const CursorBuilder._());
    final cursor = _Cursor(
      [for (final v in values) v._field],
      [for (final v in values) v._value],
      inclusive: inclusive,
    );
    _checkCursor(cursor);
    return cursor;
  }

  /// Throws a [StateError] unless [cursor] has one value for each of the
  /// first fields the query is ordered by, in that order.
  void _checkCursor(_Cursor cursor) {
    final orders = _effectiveOrders;
    if (cursor.fields.isEmpty) throw ArgumentError.value(cursor.fields, 'values', 'cannot be empty');
    if (cursor.fields.length > orders.length) {
      throw StateError(
        'A cursor has ${cursor.fields.length} values but the query is ordered by ${orders.length} fields.',
      );
    }
    for (var i = 0; i < cursor.fields.length; i++) {
      if (cursor.fields[i].name != orders[i].field.name) {
        throw StateError(
          'The cursor value ${i + 1} is for ${cursor.fields[i].name}, '
          'but the query is ordered by ${orders[i].field.name} at that position.',
        );
      }
    }
  }

  /// [startAt], with the values read off [document].
  Query<T> startAtDocument(DocumentSnapshot<T> document) =>
      _with(_spec.copyWith(start: _documentCursor(document, inclusive: true)));

  /// [startAfter], with the values read off [document].
  Query<T> startAfterDocument(DocumentSnapshot<T> document) =>
      _with(_spec.copyWith(start: _documentCursor(document, inclusive: false)));

  /// [endAt], with the values read off [document].
  Query<T> endAtDocument(DocumentSnapshot<T> document) =>
      _with(_spec.copyWith(end: _documentCursor(document, inclusive: true)));

  /// [endBefore], with the values read off [document].
  Query<T> endBeforeDocument(DocumentSnapshot<T> document) =>
      _with(_spec.copyWith(end: _documentCursor(document, inclusive: false)));

  /// Runs the query once.
  Future<QuerySnapshot<T>> get() async {
    final docs = await _fetch(_reach());
    return QuerySnapshot._(docs, _diff<T>(null, docs));
  }

  /// Runs the query now, then again after every write to its collection made
  /// through a [Collection], [DocumentReference], [WriteBatch] or
  /// [Transaction], emitting a [QuerySnapshot] each time the result differs.
  ///
  /// Nothing runs until the stream is listened to, and it stops when the
  /// listener cancels.
  ///
  /// On an isolated collection it follows [Tenant]: after [Tenant.use] the
  /// next snapshot is the new tenant's documents from scratch — every one
  /// added, none of the previous tenant's carried over as removed.
  Stream<QuerySnapshot<T>> snapshots() {
    late final StreamController<QuerySnapshot<T>> controller;
    StreamSubscription<void>? subscription;
    StreamSubscription<void>? tenantSubscription;
    List<QueryDocumentSnapshot<T>>? previous;
    var running = false;
    var dirty = false;
    var startOver = false;

    Future<void> refresh() async {
      if (running) {
        dirty = true;
        return;
      }
      running = true;
      try {
        do {
          dirty = false;
          final reach = _reach();
          final docs = await _fetch(reach);
          if (controller.isClosed) return;
          if (reach != _reach()) {
            // the tenant changed while reading: what came back is not theirs
            startOver = dirty = true;
            continue;
          }
          if (startOver) previous = null;
          startOver = false;
          final changes = _diff<T>(previous, docs);
          if (previous == null || changes.isNotEmpty) {
            controller.add(QuerySnapshot._(docs, changes));
          }
          previous = docs;
        } while (dirty && !controller.isClosed);
      } catch (error, stackTrace) {
        if (!controller.isClosed) controller.addError(error, stackTrace);
      } finally {
        running = false;
      }
    }

    controller = StreamController<QuerySnapshot<T>>(
      onListen: () {
        subscription = _ChangeBus.changes(_collection.name).listen((_) => unawaited(refresh()));
        if (_scope is _CurrentScope && _collection.tunnel == Tunnel.isolated) {
          tenantSubscription = Tenant.changes.listen((_) {
            startOver = true;
            unawaited(refresh());
          });
        }
        unawaited(refresh());
      },
      onCancel: () async {
        await subscription?.cancel();
        await tenantSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  /// How many documents match, honouring [limit].
  Future<int> count() async => _number(await _aggregate('COUNT(*)'))!.toInt();

  /// The sum of [field] over the matching documents, `0` when none has it.
  Future<num> sum<N extends num>(Field<N> field) async =>
      _number(await _aggregate('SUM(${_fieldExpression(field)})')) ?? 0;

  /// The average of [field] over the matching documents, `null` when none has
  /// it.
  Future<double?> average<N extends num>(Field<N> field) async =>
      _number(await _aggregate('AVG(${_fieldExpression(field)})'))?.toDouble();

  Future<DatabaseType?> _aggregate(String expression) async {
    final reach = _reach();
    await _collection._ensure();
    final compiled = _select(reach);
    final rows = await AppStorage.database.rawQuery('SELECT $expression AS value FROM (${compiled.sql})', compiled.args);
    return rows.single['value'];
  }

  Future<List<QueryDocumentSnapshot<T>>> _fetch(_Reach reach) async {
    await _collection._ensure();
    final compiled = _select(reach);
    final rows = await AppStorage.database.rawQuery(compiled.sql, compiled.args);
    final docs = [for (final row in rows) _collection._documentOf(row, pinRows: reach.isMany)];
    return _spec.limitToLast ? docs.reversed.toList() : docs;
  }

  /// The orders the query sorts by, the document id always last so that ties
  /// — and a query with no [orderBy] at all — come back in a stable order.
  List<_Order> get _effectiveOrders {
    final orders = _spec.orders;
    if (orders.isEmpty) {
      return const [_Order(Field.documentId, descending: false)];
    }
    if (orders.any((order) => _isDocumentId(order.field))) return orders;
    return [...orders, _Order(Field.documentId, descending: orders.last.descending)];
  }

  /// A cursor at [document], on every field the query is ordered by.
  _Cursor _documentCursor(DocumentSnapshot<T> document, {required bool inclusive}) {
    if (!document.exists) {
      throw ArgumentError.value(document, 'document', 'does not exist');
    }
    final orders = _effectiveOrders;
    return _Cursor(
      [for (final order in orders) order.field],
      [
        for (final order in orders)
          document._valueAt(order.field) ??
              (throw ArgumentError.value(document, 'document', 'has no ${order.field.name} to start from')),
      ],
      inclusive: inclusive,
    );
  }

  _Compiled _select(_Reach reach) {
    if (_spec.limitToLast && _spec.orders.isEmpty) {
      throw StateError('limitToLast needs an orderBy: without one there is no telling which documents are last.');
    }
    if (reach.isMany && (_spec.start != null || _spec.end != null)) {
      throw StateError('Cursors are not available on acrossTenants(): the same id can come back once per tenant.');
    }

    final conditions = <String>[];
    final args = <DatabaseType>[];

    // The partition comes first, and no method of this class can leave it out.
    if (!reach.isMany) {
      conditions.add('tenant = ?');
      args.add(DatabaseType.varchar(reach.tenant!));
    } else if (reach.only case final only?) {
      if (only.isEmpty) throw ArgumentError.value(only, 'only', 'cannot be empty');
      conditions.add('tenant IN (${_placeholders(only.length)})');
      args.addAll(only.map(DatabaseType.varchar));
    }

    for (final filter in _spec.filters) {
      final compiled = filter._compile();
      conditions.add(compiled.sql);
      args.addAll(compiled.args);
    }

    final orders = _effectiveOrders;
    for (final order in _spec.orders) {
      if (!_isDocumentId(order.field)) {
        conditions.add('${_fieldExpression(order.field)} IS NOT NULL');
      }
    }

    void addCursor(_Cursor cursor, {required bool isStart}) {
      _checkCursor(cursor);
      final alternatives = <String>[];
      final equalities = <String>[];
      final equalityArgs = <DatabaseType>[];
      for (var i = 0; i < cursor.values.length; i++) {
        final expression = _fieldExpression(orders[i].field);
        final value = _operand(cursor.values[i]);
        final operator = (isStart == !orders[i].descending) ? '>' : '<';
        alternatives.add('(${[...equalities, '$expression $operator ?'].join(' AND ')})');
        args.addAll([...equalityArgs, value]);
        equalities.add('$expression = ?');
        equalityArgs.add(value);
      }
      if (cursor.inclusive) {
        alternatives.add('(${equalities.join(' AND ')})');
        args.addAll(equalityArgs);
      }
      conditions.add('(${alternatives.join(' OR ')})');
    }

    if (_spec.start case final start?) addCursor(start, isStart: true);
    if (_spec.end case final end?) addCursor(end, isStart: false);

    final flip = _spec.limitToLast;
    final orderBy = orders
        .map((order) => '${_fieldExpression(order.field)} ${order.descending != flip ? 'DESC' : 'ASC'}')
        .join(', ');
    final tieBreak = reach.isMany ? ', tenant ${flip ? 'DESC' : 'ASC'}' : '';

    final sql = StringBuffer('SELECT tenant, id, data, created_at, updated_at FROM "${_collection.name}"');
    if (conditions.isNotEmpty) sql.write(' WHERE ${conditions.join(' AND ')}');
    sql.write(' ORDER BY $orderBy$tieBreak');
    if (_spec.limit != null) sql.write(' LIMIT ${_spec.limit}');
    return (sql: sql.toString(), args: args);
  }
}
