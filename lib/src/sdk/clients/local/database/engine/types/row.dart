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

/// Reads a column out of a [RawRow] by name, and says in the type
/// whether it may be NULL.
///
/// `row['title']!` fails with a null check that names nothing, and a NULL
/// column read with `asString` fails deep inside the decoder. These two
/// methods fail at the column instead, naming it, and split the two cases so
/// the compiler holds the difference: [required] never answers a [Nil], and
/// [nullable] answers a `Value?`, so forgetting the `?.` before a
/// decoder does not compile.
///
/// ```dart
/// static Todo fromRow(RawRow row) => Todo(
///   title: row.required('title').asString,
///   note: row.nullable('note')?.asString,
/// );
/// ```
extension RowReading on RawRow {
  /// The value of [column], for a column that is never NULL.
  ///
  /// Throws a [StateError] naming [column] and the columns the row does carry
  /// when it has no such column, which is a typo or a `select` that left it
  /// out. Throws a [StateError] naming [column] when it is NULL, in which
  /// case the column is [nullable], and the decoder would only have failed
  /// later with a message that names no column.
  Value required(String column) {
    final value = _lookup(column);
    if (value is Nil) {
      throw StateError('Column "$column" is NULL where a value was required. Read a nullable column with nullable.');
    }
    return value;
  }

  /// The value of [column], or `null` when it is NULL.
  ///
  /// Throws a [StateError] naming [column] and the columns the row does carry
  /// when it has no such column: a missing column is a mistake, not a NULL.
  Value? nullable(String column) {
    final value = _lookup(column);
    return value is Nil ? null : value;
  }

  Value _lookup(String column) =>
      this[column] ?? (throw StateError('The row has no column "$column". Its columns are: ${keys.join(', ')}.'));
}
