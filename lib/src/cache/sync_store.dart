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

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'cache.dart';

const _table = 'sync_cache';

/// Where [CacheEntry] survives, per entry rather than per collection.
///
/// What reading without the network is built on: a `CachePolicy` decides
/// whether an entry is still worth trusting, this decides where it lives. Two
/// implementations are given, [MemorySyncStore] for a test and
/// [SqfliteSyncStore] for production, the same split the credential's own store
/// has between memory and the vault.
abstract interface class SyncStore {
  /// The entry stored under [key], or `null` when there is none.
  Future<CacheEntry?> read(String key);

  /// Stores [entry], replacing whatever was held under [entry.key].
  Future<void> write(CacheEntry entry);

  /// Marks [key] as deleted rather than removing it, so a caller that reads
  /// it back afterwards learns it was deleted instead of finding nothing.
  ///
  /// Safe to call on a key nothing was ever written under.
  Future<void> markDeleted(String key);

  /// Removes every tombstone marked deleted longer than [olderThan] ago.
  ///
  /// Never removes an entry that is not a tombstone: this is housekeeping
  /// for [markDeleted], not a general eviction policy.
  Future<void> purgeTombstones({required Duration olderThan});

  /// Removes every entry, tombstoned or not.
  Future<void> clear();
}

/// A [SyncStore] that forgets everything when the process ends.
///
/// What a test runs against, the same role the credential's in-memory store
/// plays for a credential.
class MemorySyncStore implements SyncStore {
  final DateTime Function() _now;
  final Map<String, CacheEntry> _entries = {};

  /// Starts out empty. [now] stands in for [DateTime.now], so a test can
  /// drive [purgeTombstones] and freshness without a real wait.
  MemorySyncStore({DateTime Function()? now}) : _now = now ?? DateTime.now;

  @override
  Future<CacheEntry?> read(String key) async => _entries[key];

  @override
  Future<void> write(CacheEntry entry) async => _entries[entry.key] = entry;

  @override
  Future<void> markDeleted(String key) async {
    final existing = _entries[key];
    _entries[key] = CacheEntry(
      key: key,
      value: existing?.value ?? '',
      version: existing?.version,
      fetchedAt: _now(),
      deleted: true,
    );
  }

  @override
  Future<void> purgeTombstones({required Duration olderThan}) async {
    final cutoff = _now().subtract(olderThan);
    _entries.removeWhere(
      (_, entry) => entry.deleted && entry.fetchedAt.isBefore(cutoff),
    );
  }

  @override
  Future<void> clear() async => _entries.clear();
}

/// A [SyncStore] backed by a dedicated `sqflite` table.
///
/// Kept separate from `LocalStorage`'s own table: `LocalStorage` is a plain
/// opaque cache with no notion of a version or a tombstone, and a project
/// that only wants that keeps using it exactly as before.
class SqfliteSyncStore implements SyncStore {
  final String _name;
  final DateTime Function() _now;
  Database? _db;

  /// Opens the database file called [name], inside the platform's own
  /// databases directory, once [open] runs. [now] stands in for
  /// [DateTime.now] in a test.
  SqfliteSyncStore({String name = 'pylon_sync.db', DateTime Function()? now})
    : _name = name,
      _now = now ?? DateTime.now;

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
        'key TEXT PRIMARY KEY, '
        'value TEXT NOT NULL, '
        'version TEXT, '
        'fetched_at INTEGER NOT NULL, '
        'deleted INTEGER NOT NULL DEFAULT 0'
        ')',
      ),
    );
  }

  @override
  Future<CacheEntry?> read(String key) async {
    final rows = await _requireOpen().query(
      _table,
      where: 'key = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  @override
  Future<void> write(CacheEntry entry) async {
    await _requireOpen().insert(_table, {
      'key': entry.key,
      'value': entry.value,
      'version': entry.version,
      'fetched_at': entry.fetchedAt.millisecondsSinceEpoch,
      'deleted': entry.deleted ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> markDeleted(String key) async {
    final existing = await read(key);
    await write(
      CacheEntry(
        key: key,
        value: existing?.value ?? '',
        version: existing?.version,
        fetchedAt: _now(),
        deleted: true,
      ),
    );
  }

  @override
  Future<void> purgeTombstones({required Duration olderThan}) async {
    final cutoff = _now().subtract(olderThan).millisecondsSinceEpoch;
    await _requireOpen().delete(
      _table,
      where: 'deleted = 1 AND fetched_at < ?',
      whereArgs: [cutoff],
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

  CacheEntry _fromRow(Map<String, Object?> row) => CacheEntry(
    key: row['key'] as String,
    value: row['value'] as String,
    version: row['version'] as String?,
    fetchedAt: DateTime.fromMillisecondsSinceEpoch(row['fetched_at'] as int),
    deleted: (row['deleted'] as int) == 1,
  );

  Database _requireOpen() {
    final db = _db;
    if (db == null) {
      throw StateError('SqfliteSyncStore is not open. Call open() first.');
    }
    return db;
  }
}
