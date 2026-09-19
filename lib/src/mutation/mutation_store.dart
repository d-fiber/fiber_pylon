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

import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'mutation.dart';

const _table = 'sync_mutations';

/// Where a [QueuedMutation] survives from the moment it is enqueued to the
/// moment it is confirmed, including across a restart.
///
/// The write half of offline-first: a mutation is durable here before any
/// network attempt is made, which is what makes it safe to retry after the
/// app is killed mid-attempt rather than merely mid-process. Two
/// implementations are given, [MemoryMutationStore] for a test and
/// [SqfliteMutationStore] for production.
abstract interface class MutationStore {
  /// Every mutation still waiting, oldest first.
  Future<List<QueuedMutation>> readAll();

  /// Appends [payload] durably, before any network attempt is made, and
  /// hands back the [QueuedMutation] it was given, with a fresh
  /// [QueuedMutation.idempotencyKey].
  Future<QueuedMutation> enqueue(String payload);

  /// Replaces the payload held under [idempotencyKey], keeping its position
  /// and its key.
  ///
  /// What a resolved conflict writes back: the mutation is still the same
  /// one, waiting under the same key, only its content changed.
  Future<void> update(String idempotencyKey, String payload);

  /// Removes the mutation stored under [idempotencyKey].
  Future<void> remove(String idempotencyKey);

  /// Removes every mutation.
  Future<void> clear();
}

/// A [MutationStore] that forgets everything when the process ends.
///
/// What a test runs against, the same role the credential's in-memory store
/// plays for a credential.
class MemoryMutationStore implements MutationStore {
  final DateTime Function() _now;
  final Random _random;
  final List<QueuedMutation> _mutations = [];

  /// Starts out empty. [now] stands in for [DateTime.now] and [random] for
  /// the source [_generateKey] draws from, so a test can predict both.
  MemoryMutationStore({DateTime Function()? now, Random? random})
    : _now = now ?? DateTime.now,
      _random = random ?? Random();

  @override
  Future<List<QueuedMutation>> readAll() async =>
      List.unmodifiable(_mutations);

  @override
  Future<QueuedMutation> enqueue(String payload) async {
    final mutation = QueuedMutation(
      idempotencyKey: _generateKey(),
      payload: payload,
      enqueuedAt: _now(),
    );
    _mutations.add(mutation);
    return mutation;
  }

  @override
  Future<void> update(String idempotencyKey, String payload) async {
    final index = _mutations.indexWhere(
      (m) => m.idempotencyKey == idempotencyKey,
    );
    if (index == -1) return;
    _mutations[index] = QueuedMutation(
      idempotencyKey: idempotencyKey,
      payload: payload,
      enqueuedAt: _mutations[index].enqueuedAt,
    );
  }

  @override
  Future<void> remove(String idempotencyKey) async =>
      _mutations.removeWhere((m) => m.idempotencyKey == idempotencyKey);

  @override
  Future<void> clear() async => _mutations.clear();

  String _generateKey() =>
      '${_now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';
}

/// A [MutationStore] backed by a dedicated `sqflite` table.
class SqfliteMutationStore implements MutationStore {
  final String _name;
  final DateTime Function() _now;
  final Random _random;
  Database? _db;

  /// Opens the database file called [name], inside the platform's own
  /// databases directory, once [open] runs. [now] and [random] stand in for
  /// [DateTime.now] and a default [Random] in a test.
  SqfliteMutationStore({
    String name = 'pylon_sync.db',
    DateTime Function()? now,
    Random? random,
  }) : _name = name,
       _now = now ?? DateTime.now,
       _random = random ?? Random();

  /// Whether [open] has run and [dispose] has not undone it.
  bool get isOpen => _db != null;

  /// Creates the underlying table, unless it already exists, and makes this
  /// instance usable.
  ///
  /// Calling it twice is harmless: the second call does nothing.
  Future<void> open() async {
    if (_db != null) return;
    final directory = await getDatabasesPath();
    _db = await openDatabase(
      p.join(directory, _name),
      version: 1,
      onCreate: (db, version) => db.execute(
        'CREATE TABLE $_table ('
        'seq INTEGER PRIMARY KEY AUTOINCREMENT, '
        'idempotency_key TEXT UNIQUE NOT NULL, '
        'payload TEXT NOT NULL, '
        'enqueued_at INTEGER NOT NULL'
        ')',
      ),
    );
  }

  @override
  Future<List<QueuedMutation>> readAll() async {
    final rows = await _requireOpen().query(_table, orderBy: 'seq ASC');
    return rows.map(_fromRow).toList();
  }

  @override
  Future<QueuedMutation> enqueue(String payload) async {
    final mutation = QueuedMutation(
      idempotencyKey: _generateKey(),
      payload: payload,
      enqueuedAt: _now(),
    );
    await _requireOpen().insert(_table, {
      'idempotency_key': mutation.idempotencyKey,
      'payload': mutation.payload,
      'enqueued_at': mutation.enqueuedAt.millisecondsSinceEpoch,
    });
    return mutation;
  }

  @override
  Future<void> update(String idempotencyKey, String payload) async {
    await _requireOpen().update(
      _table,
      {'payload': payload},
      where: 'idempotency_key = ?',
      whereArgs: [idempotencyKey],
    );
  }

  @override
  Future<void> remove(String idempotencyKey) async {
    await _requireOpen().delete(
      _table,
      where: 'idempotency_key = ?',
      whereArgs: [idempotencyKey],
    );
  }

  @override
  Future<void> clear() async => _requireOpen().delete(_table);

  /// Closes the database.
  ///
  /// Safe to call on an instance that was never opened, and safe to call
  /// twice.
  Future<void> dispose() async {
    await _db?.close();
    _db = null;
  }

  QueuedMutation _fromRow(Map<String, Object?> row) => QueuedMutation(
    idempotencyKey: row['idempotency_key'] as String,
    payload: row['payload'] as String,
    enqueuedAt: DateTime.fromMillisecondsSinceEpoch(row['enqueued_at'] as int),
  );

  String _generateKey() =>
      '${_now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';

  Database _requireOpen() {
    final db = _db;
    if (db == null) {
      throw StateError('SqfliteMutationStore is not open. Call open() first.');
    }
    return db;
  }
}
