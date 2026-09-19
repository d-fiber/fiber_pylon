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

/// One term of a query's order: a [Field] and the [SortOrder] it sorts in.
/// Built by [OrderBuilder].
final class DocumentOrder {
  const DocumentOrder._(this._field, this._order);

  final Field<Object> _field;
  final SortOrder _order;
}

/// Composes the orders [Query.orderBy] takes, handed to its callback — the
/// same [SortOrder] a table index and a `LocalDatabase` query use.
///
/// ```dart
/// users.orderBy((o) => [o.asc(User.city_), o.desc(User.age_)])
/// ```
final class OrderBuilder {
  const OrderBuilder._();

  /// Smallest [field] first.
  DocumentOrder asc(Field<Object> field) => DocumentOrder._(field, SortOrder.asc);

  /// Largest [field] first.
  DocumentOrder desc(Field<Object> field) => DocumentOrder._(field, SortOrder.desc);
}

/// One value a cursor starts or ends at, tied to the field it belongs to.
/// Built by [CursorBuilder].
final class CursorValue {
  const CursorValue._(this._field, this._value);

  final Field<Object> _field;
  final Object _value;
}

/// Composes the values [Query.startAt] and its siblings take, handed to their
/// callback: one value per field the query is ordered by, in that order, each
/// of the type its field holds.
///
/// ```dart
/// users.orderBy((o) => [o.asc(User.age_)]).startAfter((c) => [c(User.age_).at(28)])
/// ```
final class CursorBuilder {
  const CursorBuilder._();

  /// The value of [field] a cursor sits at.
  CursorField<V> call<V extends Object>(Field<V> field) => CursorField._(field);
}

/// The one thing a cursor can say about a [Field]: the [V] it sits at.
final class CursorField<V extends Object> {
  const CursorField._(this._field);

  final Field<V> _field;

  /// The cursor sits at [value] on this field.
  CursorValue at(V value) => CursorValue._(_field, value);
}
