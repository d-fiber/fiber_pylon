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

/// Encodes a [T] into a JSON-backed [Value.varchar] and decodes it
/// back, the same convention [PreferencesStorage] already uses for its own
/// [Preference.json_] — a column holds one [T] exactly the way a preference
/// entry does, through a [fromJson] and [toJson] a project supplies once.
/// [Value.point] is this same convention, already applied to
/// [Location]; reach for [Json] for every other shape a project
/// wants a column to hold as JSON.
///
/// ```dart
/// final class CartItem {
///   const CartItem({required this.sku, required this.quantity});
///   final String sku;
///   final int quantity;
///
///   static CartItem fromJson(Map<String, dynamic> json) =>
///       CartItem(sku: json['sku'] as String, quantity: json['quantity'] as int);
///
///   Map<String, dynamic> toJson() => {'sku': sku, 'quantity': quantity};
/// }
///
/// const cartItem = Json<CartItem>(fromJson: CartItem.fromJson, toJson: (value) => value.toJson());
///
/// final row = {'item': cartItem.encode(const CartItem(sku: 'mug-01', quantity: 2))};
/// final item = cartItem.decode(row.required('item'));
/// ```
///
/// Nothing here validates what [fromJson] does with a shape that no longer
/// matches: a stored value from an older version of a project's own [T] is
/// exactly the situation [fromJson] itself is responsible for handling, the
/// same as [PreferenceJson] leaves it.
final class Json<T> {
  /// Codes a [T] through [fromJson] and [toJson].
  const Json({required this.fromJson, required this.toJson});

  /// Rebuilds a [T] from the JSON [decode] reads back.
  final T Function(Map<String, dynamic> json) fromJson;

  /// This [T]'s own fields, in the shape [fromJson] rebuilds from.
  final Map<String, dynamic> Function(T value) toJson;

  /// Encodes [value] into a [Value.varchar] holding its JSON form.
  Value encode(T value) => Value.varchar(jsonEncode(toJson(value)));

  /// Decodes [value], read back from a column [encode] wrote.
  ///
  /// Throws a [StateError] if [value] is not a [Varchar].
  T decode(Value value) {
    if (value case Varchar(value: final stored)) {
      return fromJson(jsonDecode(stored) as Map<String, dynamic>);
    }
    throw StateError('$value is not JSON.');
  }
}

/// Encodes a `List<T>` into a JSON-backed [Value.varchar] and
/// decodes it back, each element read and written through a [fromJson] and
/// [toJson] a project supplies once for its own [T] — [Json]'s own
/// convention, applied once per element rather than once for a whole value.
///
/// [Value.list] already covers a list whose elements are native
/// JSON values on their own — an [int], a [double], a [String], a [bool],
/// a `Map<String, dynamic>` — with no [fromJson]/[toJson] to write. Reach
/// for this only when [T] is a project's own type instead.
final class ListJson<T> {
  /// Codes a `List<T>` through [fromJson] and [toJson], applied once per
  /// element.
  const ListJson({required this.fromJson, required this.toJson});

  /// Rebuilds one element from the JSON [decode] reads back.
  final T Function(Map<String, dynamic> json) fromJson;

  /// One element's own fields, in the shape [fromJson] rebuilds from.
  final Map<String, dynamic> Function(T value) toJson;

  /// Encodes [value] into a [Value.varchar] holding its JSON form.
  Value encode(List<T> value) => Value.varchar(jsonEncode(value.map(toJson).toList()));

  /// Decodes [value], read back from a column [encode] wrote.
  ///
  /// Throws a [StateError] if [value] is not a [Varchar].
  List<T> decode(Value value) {
    if (value case Varchar(value: final stored)) {
      return (jsonDecode(stored) as List<dynamic>).map((json) => fromJson(json as Map<String, dynamic>)).toList();
    }
    throw StateError('$value is not a list.');
  }
}
