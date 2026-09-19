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
sealed class StoreError extends Equatable implements Exception {
  const StoreError(this.message);

  /// sqflite's own [DatabaseException.toString], verbatim.
  final String message;

  /// Reads which [StoreError] [error] actually is, from the result code
  /// SQLite reported when there is one and from [DatabaseException]'s own
  /// message predicates otherwise, answering [UnknownError] when
  /// neither recognises it.
  factory StoreError.from(DatabaseException error) {
    final message = error.toString();
    final text = message.toLowerCase();
    final code = error.getResultCode();
    final primary = code == null ? null : code & _primaryCodeMask;
    if (code == 1555 || code == 2067 || error.isUniqueConstraintError()) {
      return UniqueConstraintError(message);
    }
    if (code == 1299 || error.isNotNullConstraintError()) return NotNullConstraintError(message);
    if (code == 787 || text.contains('foreign key constraint failed')) {
      return ForeignKeyConstraintError(message);
    }
    if (code == 275 || text.contains('check constraint failed')) return CheckConstraintError(message);
    if (code == 3091 || primary == 20 || text.contains('datatype mismatch')) {
      return DatatypeMismatchError(message);
    }
    if (error.isNoSuchTableError()) return NoSuchTableError(message);
    if (text.contains('no such column') || text.contains('has no column named')) {
      return NoSuchColumnError(message);
    }
    if (text.contains('already exists') || error.isDuplicateColumnError()) return AlreadyExistsError(message);
    if (error.isSyntaxError()) return SyntaxError(message);
    if (primary == 5 || primary == 6) return BusyError(message);
    if (primary == 8 || error.isReadOnlyError()) return ReadOnlyError(message);
    if (primary == 11 || primary == 26) return CorruptError(message);
    if (primary == 10 || primary == 13) return StorageError(message);
    if (text.contains('transaction_closed')) return TransactionClosedError(message);
    if (error.isDatabaseClosedError()) return ClosedError(message);
    if (primary == 14 || error.isOpenFailedError()) return OpenFailedError(message);
    return UnknownError(message);
  }

  @override
  List<Object?> get props => [message];

  @override
  String toString() => '$runtimeType($message)';
}

/// A write broke a `UNIQUE` (or a primary key's own implicit one) index.
final class UniqueConstraintError extends StoreError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const UniqueConstraintError(super.message);
}

/// A write left a `NOT NULL` column without a value.
final class NotNullConstraintError extends StoreError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const NotNullConstraintError(super.message);
}

/// A statement named a table that does not exist.
final class NoSuchTableError extends StoreError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const NoSuchTableError(super.message);
}

/// A statement was not valid SQL.
final class SyntaxError extends StoreError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const SyntaxError(super.message);
}

/// A write reached a database [LocalDatabase.open] opened with
/// `readOnly: true`.
final class ReadOnlyError extends StoreError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const ReadOnlyError(super.message);
}

/// Something reached a [LocalDatabase] after [LocalDatabase.dispose] closed
/// it.
final class ClosedError extends StoreError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const ClosedError(super.message);
}

/// [LocalDatabase.open] itself failed — a file this process has no permission
/// to read or write, a read only open of a file that does not exist, or a
/// failure SQLite gave no more precise reason for.
final class OpenFailedError extends StoreError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const OpenFailedError(super.message);
}

/// A write left a foreign key pointing at a row that does not exist, or removed
/// a row a foreign key still points at.
final class ForeignKeyConstraintError extends StoreError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const ForeignKeyConstraintError(super.message);
}

/// A write broke a `CHECK` constraint.
final class CheckConstraintError extends StoreError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const CheckConstraintError(super.message);
}

/// A write stored a value of a type a `STRICT` table does not accept for that
/// column.
final class DatatypeMismatchError extends StoreError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const DatatypeMismatchError(super.message);
}

/// A statement named a column that the table does not have.
final class NoSuchColumnError extends StoreError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const NoSuchColumnError(super.message);
}

/// A statement created a table, an index, a view or a trigger whose name is
/// already taken.
final class AlreadyExistsError extends StoreError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const AlreadyExistsError(super.message);
}

/// Another connection to the same file holds a lock this statement needs, and
/// the statement gave up waiting. Running it again later can succeed.
final class BusyError extends StoreError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const BusyError(super.message);
}

/// The file is not a database, or is one SQLite finds damaged.
final class CorruptError extends StoreError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const CorruptError(super.message);
}

/// The storage under the file failed: the disk or the file is full, or reading
/// or writing it failed.
final class StorageError extends StoreError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const StorageError(super.message);
}

/// A [TransactionScope] was used after its transaction had committed or
/// rolled back.
final class TransactionClosedError extends StoreError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const TransactionClosedError(super.message);
}

/// [LocalDatabase.open] found a file written by a newer schema version than
/// this code declares, and refused to read it wrongly.
final class SchemaTooNewError extends StoreError {
  /// Wraps the [message] naming both versions.
  const SchemaTooNewError(super.message);
}

/// A [LocalDatabase] was asked to encrypt its file, and the SQLite it runs on
/// cannot: it is not SQLCipher. It refused to open, rather than write in clear
/// what was meant to be unreadable.
final class EncryptionUnavailableError extends StoreError {
  /// Wraps the [message] naming the database.
  const EncryptionUnavailableError(super.message);
}

/// [LocalDatabase.open] found a declared column it cannot add to an existing
/// file by itself. Declare it nullable, give it a default, or add a migration.
final class MigrationRequiredError extends StoreError {
  /// Wraps the [message] naming the column and the reason.
  const MigrationRequiredError(super.message);
}

/// Anything [DatabaseException]'s own predicates do not recognise.
final class UnknownError extends StoreError {
  /// Wraps sqflite's own [DatabaseException.toString] as [message].
  const UnknownError(super.message);
}

const int _primaryCodeMask = 0xFF;

Future<T> _guarded<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on DatabaseException catch (error) {
    throw StoreError.from(error);
  }
}
