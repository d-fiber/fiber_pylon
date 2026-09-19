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

/// One upgrade of the schema version, run by [LocalDatabase.declared] inside
/// the transaction that upgrades the file. It receives the transaction and
/// must not reach for the [LocalDatabase] itself.
typedef Migration = Future<void> Function(DatabaseTransaction txn);

OnDatabaseConfigureFn? _configureDeclared(bool readOnly) =>
    readOnly ? null : (db) => db.rawQuery('PRAGMA journal_mode = WAL');

Future<Set<String>> _names(DatabaseExecutor executor, String sql) async {
  final rows = await executor.rawQuery(sql);
  return {for (final row in rows) row['name']! as String};
}

Future<void> _synchronizeSchema(LocalDatabase database, Database native) {
  final declared = [...?database._tables?.map((table) => table.declaration), ...database._declarations];
  DeclaredTable.checkTogether(declared);
  return _guarded(
    () => native.transaction((nativeTransaction) async {
      final txn = DatabaseTransaction._(nativeTransaction, database);
      final latest = database._migrations.length + 1;
      final stored = (await nativeTransaction.rawQuery('PRAGMA user_version')).single['user_version']! as int;
      if (stored > latest) {
        throw SchemaTooNewError(
          'The file is at schema version $stored but this code only knows version $latest. '
          'Open it with the newer code instead.',
        );
      }
      const userTables =
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite\\_%' ESCAPE '\\'";
      final isFresh = stored == 0 && (await _names(nativeTransaction, userTables)).isEmpty;
      if (!isFresh) {
        for (var version = stored < 1 ? 1 : stored; version < latest; version++) {
          await database._migrations[version - 1](txn);
        }
      }
      final existing = await _names(nativeTransaction, userTables);
      final indexes = await _names(nativeTransaction, "SELECT name FROM sqlite_master WHERE type = 'index'");
      for (final table in declared) {
        final statements = table.statements;
        if (!existing.contains(table.name)) {
          for (final statement in statements) {
            await nativeTransaction.execute(statement);
          }
          continue;
        }
        final present = (await nativeTransaction.rawQuery(
          'PRAGMA table_info(${_quotedIdentifier(table.name)})',
        )).map((row) => row['name']! as String).toSet();
        for (final column in table.columns.keys.where((name) => !present.contains(name))) {
          final String statement;
          try {
            statement = table.addColumnStatement(column);
          } on StateError catch (error) {
            throw MigrationRequiredError(
              '${table.name}.$column cannot be added to the existing file: ${error.message}',
            );
          }
          await nativeTransaction.execute(statement);
        }
        for (var position = 0; position < table.indexes.length; position++) {
          if (!indexes.contains(table.indexes[position].name)) {
            await nativeTransaction.execute(statements[position + 1]);
          }
        }
      }
      if (stored != latest) await nativeTransaction.execute('PRAGMA user_version = $latest');
    }),
  );
}
