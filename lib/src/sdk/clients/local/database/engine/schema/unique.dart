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

part of 'schema.dart';

/// A `UNIQUE` constraint that spans one or several columns.
final class UniqueConstraint extends Equatable {
  /// Built only by [TableUniqueBuilder].
  const UniqueConstraint._({required this.columns, this.name});

  /// The columns that, together, must not repeat across two rows.
  ///
  /// A row holding null in one of them never counts as a repeat.
  final List<String> columns;

  /// The name of this constraint. Unnamed when left out.
  final String? name;

  @override
  List<Object?> get props => [columns, name];
}

/// The starting point of a `UNIQUE` constraint, handed to the callback of
/// [TableBuilderBase.uniques].
final class TableUniqueFactory {
  /// Creates a factory, which [TableBuilderBase.uniques] already supplies to its
  /// callback.
  const TableUniqueFactory();

  /// Starts a constraint that [columns] must not repeat together across two
  /// rows.
  TableUniqueBuilder columns(List<String> columns) => TableUniqueBuilder._(columns);
}

/// A `UNIQUE` constraint under construction, started by
/// [TableUniqueFactory.columns] and read by [TableBuilderBase.uniques] once its
/// callback returns.
final class TableUniqueBuilder {
  TableUniqueBuilder._(this._columns);

  /// Backs [UniqueConstraint.columns].
  final List<String> _columns;

  /// Backs [UniqueConstraint.name].
  String? _name;

  /// Names this constraint.
  ///
  /// It stays unnamed when this is not called.
  TableUniqueBuilder name(String name) {
    _name = name;
    return this;
  }

  UniqueConstraint _build() => UniqueConstraint._(columns: _columns, name: _name);
}
