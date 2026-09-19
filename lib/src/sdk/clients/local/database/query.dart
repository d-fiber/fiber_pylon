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

/// A question asked of one [Collection]: which documents, in which order, how
/// many. Immutable — every method below answers a new [Query] that adds one
/// more constraint to this one.
///
/// A query is written with the columns of the table its collection is on, so
/// there is no field to misspell and no value of the wrong type:
///
/// ```dart
/// final page = await users
///     .where(usersTable.age.isGreaterThanOrEqualTo(18))
///     .orderBy([usersTable.name.asc()])
///     .limit(20)
///     .get();
/// ```
///
/// It reads the current [Tenant]'s documents and nothing else, on a table that
/// is isolated. Nothing here can reach another tenant's.
class Query<R extends Object, K extends Object> {
  const Query._(this._table, [this._filters = const [], this._orders = const [], this._limit, this._offset]);

  final KeyedTable<R, K> _table;
  final List<Filter> _filters;
  final List<Sort> _orders;
  final int? _limit;
  final int? _offset;

  Query<R, K> _copy({List<Filter>? filters, List<Sort>? orders, int? limit, int? offset}) =>
      Query._(_table, filters ?? _filters, orders ?? _orders, limit ?? _limit, offset ?? _offset);

  /// Keeps the documents [filter] matches, and those of every earlier [where].
  ///
  /// [filter] is built from the columns of this collection's table, which is
  /// checked: one that reads another table throws an [ArgumentError].
  Query<R, K> where(Filter filter) => _copy(filters: [..._filters, filter]);

  /// Sorts by [orders], after any earlier [orderBy], each later one breaking
  /// the ties of the one before it.
  Query<R, K> orderBy(List<Sort> orders) => _copy(orders: [..._orders, ...orders]);

  /// Keeps the first [count] documents.
  Query<R, K> limit(int count) => _copy(limit: RangeError.checkNotNegative(count, 'count'));

  /// Skips the first [count] documents.
  Query<R, K> offset(int count) => _copy(offset: RangeError.checkNotNegative(count, 'count'));

  Rows<R> _rows(Connection session) {
    Rows<R> rows = _table.on(session);
    for (final filter in _filters) {
      rows = rows.where(filter);
    }
    if (_orders.isNotEmpty) rows = rows.orderBy(_orders);
    final limit = _limit;
    if (limit != null) rows = rows.limit(limit);
    final offset = _offset;
    if (offset != null) rows = rows.offset(offset);
    return rows;
  }

  /// Runs the query once.
  Future<QuerySnapshot<R, K>> get() async {
    final documents = _documentsOf(_table, await _rows(LocalDatabase.instance).list());
    return QuerySnapshot._(documents, _diff(_table, null, documents));
  }

  /// The first document the query keeps, or `null` when it keeps none.
  Future<R?> first() => _rows(LocalDatabase.instance).first();

  /// How many documents match. Throws a [StateError] when a [limit] or an
  /// [offset] was set, which a count would silently ignore.
  Future<int> count() => _rows(LocalDatabase.instance).count();

  /// Runs the query now, then again after every write to its collection made
  /// through the engine, emitting a [QuerySnapshot] each time the result
  /// differs.
  ///
  /// Nothing runs until the stream is listened to, and it stops when the
  /// listener cancels. On an isolated collection it follows [Tenant]: after
  /// [Tenant.use] the next snapshot is the new tenant's documents from scratch —
  /// every one added, none of the previous tenant's carried over as removed.
  Stream<QuerySnapshot<R, K>> snapshots() {
    List<QueryDocumentSnapshot<R, K>>? previous;
    String? previousTenant;
    return _rows(LocalDatabase.instance).watch().map((records) {
      final tenant = Tenant.current;
      if (_table.tunnel == Tunnel.isolated && tenant != previousTenant) previous = null;
      previousTenant = tenant;
      final documents = _documentsOf(_table, records);
      final changes = _diff(_table, previous, documents);
      previous = documents;
      return QuerySnapshot._(documents, changes);
    });
  }
}
