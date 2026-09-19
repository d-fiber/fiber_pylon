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

/// A `UNIQUE` constraint spanning one or several columns at once.
final class UniqueConstraint extends Equatable {
  /// Built only by [TableUniqueBuilder], never by hand: a value assembled
  /// here could hold a combination the builder refuses.
  const UniqueConstraint._({required this.columns, this.name});

  /// The columns that, together, must not repeat across two rows.
  final List<String> columns;

  /// The name this constraint is created under. SQLite picks one on its
  /// own when left out.
  final String? name;

  @override
  List<Object?> get props => [columns, name];
}

/// Opens a `UNIQUE` constraint, closed by [TableUniqueBuilder.name] or read
/// directly once [TableBuilder.uniques]' own callback returns.
final class TableUniqueFactory {
  /// Opens no constraint on its own; [columns] does.
  const TableUniqueFactory();

  /// The columns that, together, must not repeat across two rows.
  TableUniqueBuilder columns(List<String> columns) => TableUniqueBuilder._(columns);
}

/// A `UNIQUE` constraint under construction, opened by
/// [TableUniqueFactory.columns].
final class TableUniqueBuilder {
  TableUniqueBuilder._(this._columns);

  final List<String> _columns;
  String? _name;

  /// The name this constraint is created under. SQLite picks one on its
  /// own when left out.
  TableUniqueBuilder name(String name) {
    _name = name;
    return this;
  }

  UniqueConstraint _build() => UniqueConstraint._(columns: _columns, name: _name);
}
