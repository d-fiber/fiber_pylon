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

/// One column [LocalDatabase.columns] read out of `PRAGMA table_xinfo`.
final class ColumnInfo extends Equatable {
  /// Wraps every field [LocalDatabase.columns] read for one column.
  const ColumnInfo({
    required this.name,
    required this.declaredType,
    required this.isNotNull,
    required this.primaryKeyPosition,
    this.defaultSql,
    this.generated,
  });

  /// The column's own name.
  final String name;

  /// The type exactly as the `CREATE TABLE` that declared it wrote it, or an
  /// empty string when the column carries none, since SQLite never requires
  /// one.
  final String declaredType;

  /// Whether the column carries a `NOT NULL` constraint.
  ///
  /// SQLite reports false for an `INTEGER PRIMARY KEY` in a table that keeps
  /// its rowid, because a null there asks for the next id instead of being
  /// stored.
  final bool isNotNull;

  /// The place of this column in the table's primary key, counting from 1,
  /// or 0 when the column is not part of it.
  final int primaryKeyPosition;

  /// The default exactly as SQLite stored it: `0`, `'open'`, `X'00ff'` or an
  /// expression's own text, without the parentheses a `CREATE TABLE` wrapped
  /// it in. Null when the column has no default.
  final String? defaultSql;

  /// Whether SQLite computes this column from the rest of the row, and how.
  /// Null for an ordinary column.
  final GeneratedStorage? generated;

  /// Whether the column is part of the table's primary key.
  bool get isPrimaryKey => primaryKeyPosition > 0;

  /// [declaredType] as one of the five [ColumnType]s a `STRICT` table takes,
  /// whatever its case. Null when it is anything else, such as `VARCHAR(20)`
  /// or no type at all.
  ColumnType? get type {
    final declared = declaredType.toUpperCase();
    for (final candidate in ColumnType.values) {
      if (candidate.name.toUpperCase() == declared) return candidate;
    }
    return null;
  }

  factory ColumnInfo._fromRow(RawRow row) => ColumnInfo(
    name: row['name']!.asString,
    declaredType: row['type']!.asString,
    isNotNull: row['notnull']!.asBoolean,
    primaryKeyPosition: row['pk']!.asInt,
    defaultSql: switch (row['dflt_value']) {
      Varchar(:final value) => value,
      _ => null,
    },
    generated: switch (row['hidden']?.asInt) {
      2 => GeneratedStorage.virtual,
      3 => GeneratedStorage.stored,
      _ => null,
    },
  );

  @override
  List<Object?> get props => [name, declaredType, isNotNull, primaryKeyPosition, defaultSql, generated];
}
