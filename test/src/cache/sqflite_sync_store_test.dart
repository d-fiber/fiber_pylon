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

// A schema-validation check, not a unit test: it opens a real, temporary
// SQLite file through `sqflite_common_ffi` to prove the raw `CREATE TABLE`
// statements `SqfliteSyncStore` writes are actually valid SQL and round-trip real
// data, something no in-memory fake can catch. Kept in its own file, outside
// the fakes-only suite discipline the rest of pylon's tests hold.

import 'dart:io';

import 'package:fiber_pylon/fiber_pylon.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

void main() {
  late Directory directory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pylon_sync_schema');
    databaseFactoryFfi.setDatabasesPath(directory.path);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  group('SqfliteSyncStore', () {
    test('creates its table and round-trips a real entry', () async {
      final store = SqfliteSyncStore(name: 'sync_cache.db');
      await store.open();
      final entry = CacheEntry(
        key: 'brand/1',
        value: '{"name":"Acme"}',
        version: 'v3',
        fetchedAt: DateTime(2026, 1, 1),
      );

      await store.write(entry);

      expect(await store.read('brand/1'), entry);
      await store.dispose();
    });

    test('purges a tombstone written to the real table', () async {
      var now = DateTime(2026, 1, 1);
      final store = SqfliteSyncStore(name: 'sync_cache_purge.db', now: () => now);
      await store.open();
      await store.markDeleted('brand/1');

      now = DateTime(2026, 1, 10);
      await store.purgeTombstones(olderThan: const Duration(days: 5));

      expect(await store.read('brand/1'), isNull);
      await store.dispose();
    });
  });
}
