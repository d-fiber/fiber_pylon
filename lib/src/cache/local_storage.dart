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

const _table = 'cache';

/// A disk-backed key-value cache, for a backend that answers over the wire
/// and would rather hand back what it already has than make every caller
/// wait on the network again.
///
/// One table, one shape: [key], the value exactly as [write] was given it,
/// and when it stops being worth trusting. What a key names, and what the
/// value holds, is entirely the project's business: this writes the string
/// it is handed and never looks inside it, so a caller encodes and decodes
/// its own shape, the same discipline a response body is read with elsewhere
/// in pylon.
///
/// A backend that keeps everything on the device already has its data; this
/// is for the one that does not, and only for answers worth serving stale
/// for a while, since nothing here knows when a call should be retried
/// instead.
class LocalStorage {
  final String _name;
  Database? _db;

  /// Opens the database file called [name], inside the platform's own
  /// databases directory, once [open] runs.
  LocalStorage({String name = 'pylon_cache.db'}) : _name = name;

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
        'expires_at INTEGER'
        ')',
      ),
    );
  }

  /// The value stored under [key], or `null` when there is none, or when it
  /// was written with a [write] that has since expired.
  ///
  /// An expired entry is deleted here rather than left for a later caller to
  /// trip over.
  Future<String?> read(String key) async {
    final rows = await _requireOpen().query(
      _table,
      where: 'key = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty) return null;

    final expiresAt = rows.first['expires_at'] as int?;
    if (expiresAt != null &&
        expiresAt <= DateTime.now().millisecondsSinceEpoch) {
      await delete(key);
      return null;
    }
    return rows.first['value'] as String;
  }

  /// Stores [value] under [key], replacing whatever was there.
  ///
  /// [ttl] is how long [value] stays worth trusting, `null` for one that
  /// never expires on its own.
  Future<void> write(String key, String value, {Duration? ttl}) async {
    final expiresAt = ttl == null
        ? null
        : DateTime.now().add(ttl).millisecondsSinceEpoch;
    await _requireOpen().insert(_table, {
      'key': key,
      'value': value,
      'expires_at': expiresAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Removes the entry stored under [key], if there is one.
  Future<void> delete(String key) async {
    await _requireOpen().delete(_table, where: 'key = ?', whereArgs: [key]);
  }

  /// Removes every entry.
  Future<void> clear() async {
    await _requireOpen().delete(_table);
  }

  /// Closes the database.
  ///
  /// Safe to call on an instance that was never opened, and safe to call
  /// twice.
  Future<void> dispose() async {
    await _db?.close();
    _db = null;
  }

  Database _requireOpen() {
    final db = _db;
    if (db == null) {
      throw StateError('LocalStorage is not open. Call open() first.');
    }
    return db;
  }
}
