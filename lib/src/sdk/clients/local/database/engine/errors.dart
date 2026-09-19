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

/// What went wrong inside SQLite, closed over the causes [DatabaseException]
/// can actually distinguish, through the result code SQLite reported and its own
/// message-matching predicates, rather than a project matching sqflite's raw
/// exception text a second time for itself.
sealed class DatabaseError extends Equatable implements Exception {
  const DatabaseError(this.message);

  /// sqflite's own [DatabaseException.toString], verbatim.
  final String message;

  /// Reads which [DatabaseError] [error] actually is, from the result code
  /// SQLite reported when there is one and from [DatabaseException]'s own
  /// message predicates otherwise, answering [DatabaseUnknownError] when
  /// neither recognises it.
  factory DatabaseError.from(DatabaseException error) {
    final message = error.toString();
    final text = message.toLowerCase();
    final code = error.getResultCode();
    final primary = code == null ? null : code & _primaryCodeMask;
    if (code == 1555 || code == 2067 || error.isUniqueConstraintError()) {
      return DatabaseUniqueConstraintError(message);
    }
    if (code == 1299 || error.isNotNullConstraintError()) return DatabaseNotNullConstraintError(message);
    if (code == 787 || text.contains('foreign key constraint failed')) {
      return DatabaseForeignKeyConstraintError(message);
    }
    if (code == 275 || text.contains('check constraint failed')) return DatabaseCheckConstraintError(message);
    if (code == 3091 || primary == 20 || text.contains('datatype mismatch')) {
      return DatabaseDatatypeMismatchError(message);
    }
    if (error.isNoSuchTableError()) return DatabaseNoSuchTableError(message);
    if (text.contains('no such column') || text.contains('has no column named')) {
      return DatabaseNoSuchColumnError(message);
    }
    if (text.contains('already exists') || error.isDuplicateColumnError()) return DatabaseAlreadyExistsError(message);
    if (error.isSyntaxError()) return DatabaseSyntaxError(message);
    if (primary == 5 || primary == 6) return DatabaseBusyError(message);
    if (primary == 8 || error.isReadOnlyError()) return DatabaseReadOnlyError(message);
    if (primary == 11 || primary == 26) return DatabaseCorruptError(message);
    if (primary == 10 || primary == 13) return DatabaseStorageError(message);
    if (text.contains('transaction_closed')) return DatabaseTransactionClosedError(message);
    if (error.isDatabaseClosedError()) return DatabaseClosedError(message);
    if (primary == 14 || error.isOpenFailedError()) return DatabaseOpenFailedError(message);
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

/// [LocalDatabase.open] itself failed — a file this process has no permission
/// to read or write, a read only open of a file that does not exist, or a
/// failure SQLite gave no more precise reason for.
final class DatabaseOpenFailedError extends DatabaseError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const DatabaseOpenFailedError(super.message);
}

/// A write left a foreign key pointing at a row that does not exist, or removed
/// a row a foreign key still points at.
final class DatabaseForeignKeyConstraintError extends DatabaseError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const DatabaseForeignKeyConstraintError(super.message);
}

/// A write broke a `CHECK` constraint.
final class DatabaseCheckConstraintError extends DatabaseError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const DatabaseCheckConstraintError(super.message);
}

/// A write stored a value of a type a `STRICT` table does not accept for that
/// column.
final class DatabaseDatatypeMismatchError extends DatabaseError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const DatabaseDatatypeMismatchError(super.message);
}

/// A statement named a column that the table does not have.
final class DatabaseNoSuchColumnError extends DatabaseError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const DatabaseNoSuchColumnError(super.message);
}

/// A statement created a table, an index, a view or a trigger whose name is
/// already taken.
final class DatabaseAlreadyExistsError extends DatabaseError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const DatabaseAlreadyExistsError(super.message);
}

/// Another connection to the same file holds a lock this statement needs, and
/// the statement gave up waiting. Running it again later can succeed.
final class DatabaseBusyError extends DatabaseError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const DatabaseBusyError(super.message);
}

/// The file is not a database, or is one SQLite finds damaged.
final class DatabaseCorruptError extends DatabaseError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const DatabaseCorruptError(super.message);
}

/// The storage under the file failed: the disk or the file is full, or reading
/// or writing it failed.
final class DatabaseStorageError extends DatabaseError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const DatabaseStorageError(super.message);
}

/// A [DatabaseTransaction] was used after its transaction had committed or
/// rolled back.
final class DatabaseTransactionClosedError extends DatabaseError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const DatabaseTransactionClosedError(super.message);
}

/// [LocalDatabase.open] found a file written by a newer schema version than
/// this code declares, and refused to read it wrongly.
final class DatabaseSchemaTooNewError extends DatabaseError {
  /// Wraps the [message] naming both versions.
  const DatabaseSchemaTooNewError(super.message);
}

/// A [LocalDatabase] was asked to encrypt its file, and the SQLite it runs on
/// cannot: it is not SQLCipher. It refused to open, rather than write in clear
/// what was meant to be unreadable.
final class DatabaseEncryptionUnavailableError extends DatabaseError {
  /// Wraps the [message] naming the database.
  const DatabaseEncryptionUnavailableError(super.message);
}

/// [LocalDatabase.open] found a declared column it cannot add to an existing
/// file by itself. Declare it nullable, give it a default, or add a migration.
final class DatabaseMigrationRequiredError extends DatabaseError {
  /// Wraps the [message] naming the column and the reason.
  const DatabaseMigrationRequiredError(super.message);
}

/// Anything [DatabaseException]'s own predicates do not recognise.
final class DatabaseUnknownError extends DatabaseError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const DatabaseUnknownError(super.message);
}

const int _primaryCodeMask = 0xFF;

Future<T> _guarded<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on DatabaseException catch (error) {
    throw DatabaseError.from(error);
  }
}
