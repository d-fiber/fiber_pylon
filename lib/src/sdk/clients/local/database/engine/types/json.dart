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

/// A codec that stores one [T] in a text column as JSON and reads it back.
///
/// The project supplies [fromJson] and [toJson] once, as it does for
/// [Preference.json_]. Use this for any project type a column must
/// hold. The location shapes have their own factories, such as [Value.point].
///
/// A list of [T] is handled by [ListJson], and a list of native JSON values by
/// [Value.list].
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
/// A row written by an older version of [T] reaches [fromJson] as it was
/// stored, and nothing here checks it, so [fromJson] must tolerate the shapes
/// earlier versions wrote.
final class Json<T> {
  /// Creates a codec that stores a [T] through [toJson] and reads it back through [fromJson].
  const Json({required this.fromJson, required this.toJson});

  /// Builds a [T] from the JSON object [decode] reads.
  final T Function(Map<String, dynamic> json) fromJson;

  /// The JSON object that [encode] stores for a [T].
  final Map<String, dynamic> Function(T value) toJson;

  /// The [Varchar] holding [value] as JSON, ready to write to a column.
  Value encode(T value) => Value.varchar(jsonEncode(toJson(value)));

  /// The [T] that [value] holds, read from a column written through [encode].
  ///
  /// Throws a [StateError] if [value] is not a [Varchar]. Throws a [FormatException] or a
  /// [TypeError] if its text is not what [encode] wrote.
  T decode(Value value) {
    if (value case Varchar(value: final stored)) {
      return fromJson(jsonDecode(stored) as Map<String, dynamic>);
    }
    throw StateError('$value is not JSON.');
  }
}

/// A codec that stores a `List<T>` in a text column as JSON and reads it back.
///
/// It works like [Json], with [fromJson] and [toJson] applied to each element.
/// A list of native JSON values needs no codec, use [Value.list] for it. Use
/// this one only when [T] is a project type.
final class ListJson<T> {
  /// Creates a codec that stores each element through [toJson] and reads it back through [fromJson].
  const ListJson({required this.fromJson, required this.toJson});

  /// Builds one element from the JSON object [decode] reads.
  final T Function(Map<String, dynamic> json) fromJson;

  /// The JSON object that [encode] stores for one element.
  final Map<String, dynamic> Function(T value) toJson;

  /// The [Varchar] holding [value] as a JSON array, ready to write to a column.
  Value encode(List<T> value) => Value.varchar(jsonEncode(value.map(toJson).toList()));

  /// The list that [value] holds, read from a column written through [encode].
  ///
  /// Throws a [StateError] if [value] is not a [Varchar]. Throws a [FormatException] or a
  /// [TypeError] if its text is not what [encode] wrote.
  List<T> decode(Value value) {
    if (value case Varchar(value: final stored)) {
      return (jsonDecode(stored) as List<dynamic>).map((json) => fromJson(json as Map<String, dynamic>)).toList();
    }
    throw StateError('$value is not a list.');
  }
}
