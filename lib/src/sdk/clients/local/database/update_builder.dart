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

/// One change to one field, built by [UpdateBuilder].
final class FieldChange {
  const FieldChange._(this._field, this._value);

  final FieldReference _field;

  /// What the field becomes: a value, or a [FieldValue] resolved against what
  /// it holds now.
  final Object? _value;
}

/// Composes the changes [DocumentReference.update] takes, handed to its
/// callback. Each is typed on what its field holds, so a change can only set
/// a value of that type, and only a number can be incremented.
///
/// ```dart
/// await db.users.doc('ada').update((u) => [
///   u(User.age_).increment(1),
///   u(User.city_).set('Paris'),
///   u.list(User.tags_).arrayUnion(['math']),
///   u(User.note_).delete(),
/// ]);
/// ```
final class UpdateBuilder {
  const UpdateBuilder._();

  /// The changes [field] can undergo, each taking a [V].
  FieldUpdate<V> call<V extends Object>(Field<V> field) => FieldUpdate._(field);

  /// The changes [field] can undergo, on the [E]s it holds.
  ListUpdate<E> list<E extends Object>(ListField<E> field) => ListUpdate._(field);
}

/// The changes one [Field] can undergo. Every value is a [V].
final class FieldUpdate<V extends Object> {
  const FieldUpdate._(this._field);

  final Field<V> _field;

  /// The field becomes [value].
  FieldChange set(V value) => FieldChange._(_field, value);

  /// The field is removed.
  FieldChange delete() => FieldChange._(_field, const FieldValue.delete());
}

/// What only a number can undergo.
extension NumericUpdate<V extends num> on FieldUpdate<V> {
  /// Adds [by] to the number the field holds, treating a missing or
  /// non-numeric field as `0`.
  FieldChange increment(V by) => FieldChange._(_field, FieldValue.increment(by));
}

/// What only a [DateTime] can undergo.
extension TimestampUpdate on FieldUpdate<DateTime> {
  /// The field becomes the time of the write, from this device's own clock.
  FieldChange serverTimestamp() => FieldChange._(_field, const FieldValue.serverTimestamp());
}

/// The changes one [ListField] can undergo. Every element is an [E].
final class ListUpdate<E extends Object> {
  const ListUpdate._(this._field);

  final ListField<E> _field;

  /// The field becomes [elements].
  FieldChange set(List<E> elements) => FieldChange._(_field, elements);

  /// Appends each of [elements] the list does not already contain.
  FieldChange arrayUnion(List<E> elements) => FieldChange._(_field, FieldValue.arrayUnion(elements));

  /// Removes every occurrence of each of [elements] from the list.
  FieldChange arrayRemove(List<E> elements) => FieldChange._(_field, FieldValue.arrayRemove(elements));

  /// The field is removed.
  FieldChange delete() => FieldChange._(_field, const FieldValue.delete());
}
