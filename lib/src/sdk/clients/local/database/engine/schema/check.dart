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

/// A `CHECK` constraint of a table, which may read several columns at once.
final class CheckConstraint extends Equatable {
  /// Built only by [TableCheckBuilder], never by hand: a value assembled
  /// here could hold a combination the builder refuses.
  const CheckConstraint._({required this.expression, this.name});

  /// The SQL predicate every row must satisfy, as the caller wrote it.
  ///
  /// Nothing here validates it, the same choice [ColumnBuilder.defaultExpression]
  /// makes for raw SQL no closed vocabulary covers. SQLite refuses a wrong one
  /// when the table is created.
  final String expression;

  /// The name this constraint is created under.
  ///
  /// Null leaves the constraint unnamed, and SQLite then reports a violation
  /// by the text of [expression] instead of a name.
  final String? name;

  @override
  List<Object?> get props => [expression, name];
}

/// The starting point of a `CHECK` constraint, handed to the callback of
/// [TableBuilderBase.checks].
final class TableCheckFactory {
  /// Creates a factory, which [TableBuilderBase.checks] already supplies to its
  /// callback.
  const TableCheckFactory();

  /// Starts a `CHECK` constraint that every row must satisfy [expression], a raw
  /// SQL predicate.
  TableCheckBuilder expression(String expression) => TableCheckBuilder._(expression);
}

/// A `CHECK` constraint under construction, started by
/// [TableCheckFactory.expression] and read by [TableBuilderBase.checks] once
/// its callback returns.
final class TableCheckBuilder {
  TableCheckBuilder._(this._expression);

  /// Backs [CheckConstraint.expression].
  final String _expression;

  /// Backs [CheckConstraint.name].
  String? _name;

  /// Names this constraint.
  ///
  /// Left out, the constraint stays unnamed and SQLite reports a violation by
  /// its expression.
  TableCheckBuilder name(String name) {
    _name = name;
    return this;
  }

  CheckConstraint _build() => CheckConstraint._(expression: _expression, name: _name);
}
