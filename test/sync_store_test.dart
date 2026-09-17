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

import 'package:fiber_pylon/fiber_pylon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CacheEntry.isFreshAt', () {
    final fetchedAt = DateTime(2026, 1, 1, 12);
    final entry = CacheEntry(key: 'brand/1', value: '{}', fetchedAt: fetchedAt);

    test('answers true while the ttl has not elapsed', () {
      expect(
        entry.isFreshAt(fetchedAt.add(const Duration(minutes: 4)), const Duration(minutes: 5)),
        isTrue,
      );
    });

    test('answers false once the ttl has elapsed', () {
      expect(
        entry.isFreshAt(fetchedAt.add(const Duration(minutes: 6)), const Duration(minutes: 5)),
        isFalse,
      );
    });
  });

  group('MemorySyncStore', () {
    test('answers null for a key nothing was written under', () async {
      final store = MemorySyncStore();
      expect(await store.read('brand/1'), isNull);
    });

    test('hands back exactly what was written', () async {
      final store = MemorySyncStore();
      final entry = CacheEntry(
        key: 'brand/1',
        value: '{"name":"Acme"}',
        version: 'v3',
        fetchedAt: DateTime(2026, 1, 1),
      );

      await store.write(entry);

      expect(await store.read('brand/1'), entry);
    });

    test('replaces whatever was held under the same key', () async {
      final store = MemorySyncStore();
      await store.write(
        CacheEntry(key: 'brand/1', value: 'old', fetchedAt: DateTime(2026, 1, 1)),
      );

      await store.write(
        CacheEntry(key: 'brand/1', value: 'new', fetchedAt: DateTime(2026, 1, 2)),
      );

      expect((await store.read('brand/1'))?.value, 'new');
    });

    group('markDeleted', () {
      test('turns an existing entry into a tombstone, keeping its version', () async {
        var now = DateTime(2026, 1, 1);
        final store = MemorySyncStore(now: () => now);
        await store.write(
          CacheEntry(key: 'brand/1', value: 'Acme', version: 'v3', fetchedAt: now),
        );

        now = DateTime(2026, 1, 2);
        await store.markDeleted('brand/1');

        final tombstone = await store.read('brand/1');
        expect(tombstone?.deleted, isTrue);
        expect(tombstone?.version, 'v3');
        expect(tombstone?.fetchedAt, now);
      });

      test('creates a tombstone for a key nothing was ever written under', () async {
        final store = MemorySyncStore();

        await store.markDeleted('brand/1');

        expect((await store.read('brand/1'))?.deleted, isTrue);
      });
    });

    group('purgeTombstones', () {
      test('removes a tombstone older than the given duration', () async {
        var now = DateTime(2026, 1, 1);
        final store = MemorySyncStore(now: () => now);
        await store.markDeleted('brand/1');

        now = DateTime(2026, 1, 10);
        await store.purgeTombstones(olderThan: const Duration(days: 5));

        expect(await store.read('brand/1'), isNull);
      });

      test('leaves a tombstone that has not aged past the given duration', () async {
        var now = DateTime(2026, 1, 1);
        final store = MemorySyncStore(now: () => now);
        await store.markDeleted('brand/1');

        now = DateTime(2026, 1, 2);
        await store.purgeTombstones(olderThan: const Duration(days: 5));

        expect((await store.read('brand/1'))?.deleted, isTrue);
      });

      test('never removes an entry that is not a tombstone, however old', () async {
        var now = DateTime(2026, 1, 1);
        final store = MemorySyncStore(now: () => now);
        await store.write(
          CacheEntry(key: 'brand/1', value: 'Acme', fetchedAt: now),
        );

        now = DateTime(2030, 1, 1);
        await store.purgeTombstones(olderThan: const Duration(days: 1));

        expect((await store.read('brand/1'))?.value, 'Acme');
      });
    });

    test('clear removes every entry, tombstoned or not', () async {
      final store = MemorySyncStore();
      await store.write(CacheEntry(key: 'brand/1', value: 'Acme', fetchedAt: DateTime(2026, 1, 1)));
      await store.markDeleted('brand/2');

      await store.clear();

      expect(await store.read('brand/1'), isNull);
      expect(await store.read('brand/2'), isNull);
    });
  });
}
