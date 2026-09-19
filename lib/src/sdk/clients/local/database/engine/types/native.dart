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

/// Reads back a value stored as one of SQLite's four non-null storage classes, with no convention on top.
///
/// Use these instead of casting a value to [Integer], [Real], [Varchar] or
/// [Blob] by hand: a failed cast throws a [TypeError] that says nothing about
/// the value, while these throw a [StateError] that shows it.
extension NativeDecoding on Value {
  /// This value as an [int].
  ///
  /// Throws a [StateError] if this is not an [Integer].
  int get asInt {
    if (this case Integer(value: final stored)) return stored;
    throw StateError('$this is not an integer.');
  }

  /// This value as a [double].
  ///
  /// An [Integer] is read as the [double] of the same value, because SQLite
  /// stores `3.0` as the integer `3` in a column declared `DECIMAL` or
  /// `NUMERIC`. Beyond 2^53 that conversion can round.
  ///
  /// Throws a [StateError] if this is neither a [Real] nor an [Integer].
  double get asDouble {
    if (this case Real(value: final stored)) return stored;
    if (this case Integer(value: final stored)) return stored.toDouble();
    throw StateError('$this is not a real.');
  }

  /// This value as a [String].
  ///
  /// Throws a [StateError] if this is not a [Varchar].
  String get asString {
    if (this case Varchar(value: final stored)) return stored;
    throw StateError('$this is not text.');
  }

  /// This value as raw bytes.
  ///
  /// Throws a [StateError] if this is not a [Blob].
  Uint8List get asBytes {
    if (this case Blob(value: final stored)) return stored;
    throw StateError('$this is not a blob.');
  }
}
