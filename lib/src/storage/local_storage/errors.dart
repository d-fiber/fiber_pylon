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

/// What went wrong inside SQLite, closed over the handful of causes
/// [DatabaseException] can actually distinguish, through its own
/// message-matching predicates, rather than a project matching sqflite's raw
/// exception text a second time for itself.
sealed class DatabaseError extends Equatable implements Exception {
  const DatabaseError(this.message);

  /// sqflite's own [DatabaseException.toString], verbatim.
  final String message;

  /// Reads which [DatabaseError] [error] actually is, through
  /// [DatabaseException]'s own predicates, answering
  /// [DatabaseUnknownError] when none of them recognise it.
  factory DatabaseError.from(DatabaseException error) {
    final message = error.toString();
    if (error.isUniqueConstraintError()) {
      return DatabaseUniqueConstraintError(message);
    }
    if (error.isNotNullConstraintError()) {
      return DatabaseNotNullConstraintError(message);
    }
    if (error.isNoSuchTableError()) return DatabaseNoSuchTableError(message);
    if (error.isSyntaxError()) return DatabaseSyntaxError(message);
    if (error.isReadOnlyError()) return DatabaseReadOnlyError(message);
    if (error.isDatabaseClosedError()) return DatabaseClosedError(message);
    if (error.isOpenFailedError()) return DatabaseOpenFailedError(message);
    return DatabaseUnknownError(message);
  }

  @override
  List<Object?> get props => [message];

  @override
  String toString() => '$runtimeType($message)';
}

/// A write broke a `UNIQUE` (or a primary key's own implicit one) index.
final class DatabaseUniqueConstraintError extends DatabaseError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const DatabaseUniqueConstraintError(super.message);
}

/// A write left a `NOT NULL` column without a value.
final class DatabaseNotNullConstraintError extends DatabaseError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const DatabaseNotNullConstraintError(super.message);
}

/// A statement named a table that does not exist.
final class DatabaseNoSuchTableError extends DatabaseError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const DatabaseNoSuchTableError(super.message);
}

/// A statement was not valid SQL.
final class DatabaseSyntaxError extends DatabaseError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const DatabaseSyntaxError(super.message);
}

/// A write reached a database [LocalDatabase.open] opened with
/// `readOnly: true`.
final class DatabaseReadOnlyError extends DatabaseError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const DatabaseReadOnlyError(super.message);
}

/// Something reached a [LocalDatabase] after [LocalDatabase.dispose] closed
/// it.
final class DatabaseClosedError extends DatabaseError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const DatabaseClosedError(super.message);
}

/// [LocalDatabase.open] itself failed — a corrupt file, or one this process
/// has no permission to read or write.
final class DatabaseOpenFailedError extends DatabaseError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const DatabaseOpenFailedError(super.message);
}

/// Anything [DatabaseException]'s own predicates do not recognise.
final class DatabaseUnknownError extends DatabaseError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const DatabaseUnknownError(super.message);
}

Future<T> _guarded<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on DatabaseException catch (error) {
    throw DatabaseError.from(error);
  }
}
