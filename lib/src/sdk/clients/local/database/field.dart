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

/// A field of a [Model], named once and typed by what it holds, so that
/// every query, order, cursor and update on it is checked by the compiler
/// instead of by a string typed twice.
///
/// ```dart
/// final class User implements Model {
///   static const age_ = Field<int>('age');
///   static const city_ = Field<String>('address.city');
///   static const tags_ = ListField<String>('tags');
///   final int age;
///   ...
/// }
///
/// db.users.where((w) => w(User.age_).isGreaterThanOrEqualTo(18)).orderBy((o) => [o.asc(User.city_)]).get();
/// ```
///
/// The trailing `_` is because a static member cannot share its name with the
/// instance field it names.
///
/// Nothing here takes a field as a bare string: a misspelled name or a value
/// of the wrong type stops at the field's own declaration, in one place.
abstract interface class FieldReference {
  /// The field's name, dotted for a nested one.
  String get name;
}

/// A field holding a single [V]: an [int], a [double], a [num], a [String], a
/// [bool], a [DateTime] or an [Enum].
///
/// What a query may say about it is [FilterBuilder.call]'s, and what an
/// update may do to it is [UpdateBuilder.call]'s: each accepts exactly [V]
/// as a value, so `Field<int>('age')` never meets `'18'`.
final class Field<V extends Object> implements FieldReference {
  /// The field called [name] — dotted for a nested one, made of letters,
  /// digits, `_` and `-`.
  const Field(this.name) : _isDocumentId = false;

  const Field._documentId() : name = '__name__', _isDocumentId = true;

  /// The document's own id, so a query can filter, order or paginate on it.
  static const Field<String> documentId = Field<String>._documentId();

  @override
  final String name;

  final bool _isDocumentId;

  @override
  String toString() => 'Field<$V>($name)';
}

/// A field holding a list of [E].
final class ListField<E extends Object> implements FieldReference {
  /// The field called [name] — dotted for a nested one, made of letters,
  /// digits, `_` and `-`.
  const ListField(this.name);

  @override
  final String name;

  @override
  String toString() => 'ListField<$E>($name)';
}
