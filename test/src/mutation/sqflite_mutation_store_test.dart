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
// statements `SqfliteMutationStore` writes are actually valid SQL and round-trip real
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

  group('SqfliteMutationStore', () {
    test('creates its table and preserves enqueue order across a reopen', () async {
      final store = SqfliteMutationStore(name: 'sync_mutations.db');
      await store.open();

      final first = await store.enqueue('brand/1|Acme');
      final second = await store.enqueue('brand/2|Widget');
      await store.dispose();

      final reopened = SqfliteMutationStore(name: 'sync_mutations.db');
      await reopened.open();
      final all = await reopened.readAll();

      expect(all.map((m) => m.idempotencyKey), [first.idempotencyKey, second.idempotencyKey]);
      expect(all.map((m) => m.payload), ['brand/1|Acme', 'brand/2|Widget']);
      await reopened.dispose();
    });

    test('update replaces the payload in place, keeping the same key and position', () async {
      final store = SqfliteMutationStore(name: 'sync_mutations_update.db');
      await store.open();
      final first = await store.enqueue('brand/1|Acme');
      await store.enqueue('brand/2|Widget');

      await store.update(first.idempotencyKey, 'brand/1|Acme Renamed');

      final all = await store.readAll();
      expect(all.map((m) => m.payload), ['brand/1|Acme Renamed', 'brand/2|Widget']);
      await store.dispose();
    });
  });
}
