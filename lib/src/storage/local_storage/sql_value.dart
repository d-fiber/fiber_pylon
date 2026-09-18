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

/// One value SQLite can actually store.
///
/// SQLite's own type system names exactly five storage classes — this closes
/// over them rather than accepting `Object?` and finding out only when
/// sqflite rejects, or silently mangles, something it was never meant to
/// hold. Neither `bool` nor `DateTime` are native to SQLite: use
/// [SqlValue.boolean] for the former (stored as `0`/`1`, the convention every
/// SQLite driver uses, this one included) and pick [integer] (epoch
/// milliseconds) or [text] (ISO-8601) for the latter, whichever a schema's
/// own columns already use — pylon does not guess one for a project that may
/// have already picked the other.
sealed class SqlValue extends Equatable {
  const SqlValue();

  /// A signed integer, up to 64 bits.
  const factory SqlValue.integer(int value) = SqlInteger;

  /// A floating point value.
  const factory SqlValue.real(double value) = SqlReal;

  /// UTF-8 text.
  const factory SqlValue.text(String value) = SqlText;

  /// Raw bytes, stored exactly as given.
  const factory SqlValue.blob(Uint8List value) = SqlBlob;

  /// The absence of a value.
  const factory SqlValue.nil() = SqlNull;

  /// [value] as an [SqlInteger] of `1` or `0`.
  static SqlValue boolean(bool value) => SqlInteger(value ? 1 : 0);

  /// Wraps whatever sqflite itself already handed back for one column.
  ///
  /// Throws an [ArgumentError] if [native] is not one of the native types
  /// sqflite hands back — which should never happen for a value this same
  /// class wrote through [toNative] in the first place.
  factory SqlValue.fromNative(Object? native) => switch (native) {
    null => const SqlNull(),
    final int value => SqlInteger(value),
    final double value => SqlReal(value),
    final String value => SqlText(value),
    final Uint8List value => SqlBlob(value),
    _ => throw ArgumentError.value(native, 'native', 'not a SQLite storage class'),
  };

  /// This value in the native shape sqflite itself accepts and hands back.
  Object? toNative();
}

/// The absence of a value — SQL `NULL`.
final class SqlNull extends SqlValue {
  /// SQL `NULL`. Prefer [SqlValue.nil] over calling this directly.
  const SqlNull();

  @override
  Object? toNative() => null;

  @override
  List<Object?> get props => const [];

  @override
  String toString() => 'SqlValue.nil()';
}

/// A signed integer, up to 64 bits.
final class SqlInteger extends SqlValue {
  /// Wraps [value]. Prefer [SqlValue.integer] over calling this directly.
  const SqlInteger(this.value);

  /// The wrapped integer.
  final int value;

  @override
  Object? toNative() => value;

  @override
  List<Object?> get props => [value];

  @override
  String toString() => 'SqlValue.integer($value)';
}

/// A floating point value.
final class SqlReal extends SqlValue {
  /// Wraps [value]. Prefer [SqlValue.real] over calling this directly.
  const SqlReal(this.value);

  /// The wrapped floating point value.
  final double value;

  @override
  Object? toNative() => value;

  @override
  List<Object?> get props => [value];

  @override
  String toString() => 'SqlValue.real($value)';
}

/// UTF-8 text.
final class SqlText extends SqlValue {
  /// Wraps [value]. Prefer [SqlValue.text] over calling this directly.
  const SqlText(this.value);

  /// The wrapped text.
  final String value;

  @override
  Object? toNative() => value;

  @override
  List<Object?> get props => [value];

  @override
  String toString() => 'SqlValue.text($value)';
}

/// Raw bytes, stored exactly as given.
final class SqlBlob extends SqlValue {
  /// Wraps [value]. Prefer [SqlValue.blob] over calling this directly.
  const SqlBlob(this.value);

  /// The wrapped bytes.
  final Uint8List value;

  @override
  Object? toNative() => value;

  @override
  List<Object?> get props => [value];

  @override
  String toString() => 'SqlValue.blob(${value.length} byte(s))';
}

/// One row, exactly as [LocalDatabase] reads one back or writes one out:
/// column name to [SqlValue]. What a column holds, and what its name means,
/// is entirely the caller's own schema.
typedef DatabaseRow = Map<String, SqlValue>;

Map<String, Object?> _toNativeRow(DatabaseRow row) => row.map((column, value) => MapEntry(column, value.toNative()));

DatabaseRow _fromNativeRow(Map<String, Object?> row) =>
    row.map((column, value) => MapEntry(column, SqlValue.fromNative(value)));

List<Object?>? _toNativeArgs(List<SqlValue>? arguments) => arguments?.map((value) => value.toNative()).toList();
