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

enum Mode { light, dark, system }

class Ticket {
  final String value;

  const Ticket(this.value);
}

void main() {
  group('Preference', () {
    test('answers the fallback while nothing is stored', () {
      final entry = Preference.text(
        store: MemoryKeyValueStore(),
        key: 'locale',
        fallback: 'fr',
      );

      expect(entry.value, 'fr');
      expect(entry.isSet, isFalse);
    });

    test('reads back what it wrote', () async {
      final entry = Preference.integer(
        store: MemoryKeyValueStore(),
        key: 'count',
      );

      await entry.set(7);

      expect(entry.value, 7);
    });

    test('publishes every value it is given', () async {
      final entry = Preference.flag(
        store: MemoryKeyValueStore(),
        key: 'enabled',
      );
      final seen = <bool>[];
      entry.changes.listen(seen.add);

      await entry.set(true);
      await entry.set(false);
      await pumpEventQueue();

      expect(seen, [true, false]);
      await entry.dispose();
    });

    test('publishes the fallback when cleared', () async {
      final entry = Preference.text(
        store: MemoryKeyValueStore(),
        key: 'locale',
        fallback: 'fr',
      );
      await entry.set('en');
      final seen = <String>[];
      entry.changes.listen(seen.add);

      await entry.clear();
      await pumpEventQueue();

      expect(seen, ['fr']);
      expect(entry.value, 'fr');
      await entry.dispose();
    });

    test('stores an enum by name rather than by index', () async {
      final store = MemoryKeyValueStore();
      final entry = Preference.enumeration<Mode>(
        store: store,
        key: 'mode',
        values: Mode.values,
        fallback: Mode.system,
      );

      await entry.set(Mode.dark);

      expect(store.read('mode'), 'dark');
      expect(entry.value, Mode.dark);
    });

    test('answers the fallback for a stored value that no longer decodes', () {
      final entry = Preference.enumeration<Mode>(
        store: MemoryKeyValueStore(const {'mode': 'sepia'}),
        key: 'mode',
        values: Mode.values,
        fallback: Mode.system,
      );

      expect(entry.value, Mode.system);
    });

    test('values replays what is held before publishing changes', () async {
      final entry = Preference.text(
        store: MemoryKeyValueStore(),
        key: 'locale',
        fallback: 'fr',
      );
      final seen = <String>[];
      entry.values.listen(seen.add);
      await pumpEventQueue();

      await entry.set('en');
      await pumpEventQueue();

      expect(seen, ['fr', 'en']);
      await entry.dispose();
    });
  });

  group('StoredCredential', () {
    test('reads back a credential through the encoding it was given', () async {
      final store = StoredCredential<Ticket>(
        MemoryKeyValueStore(),
        key: 'ticket',
        encode: (ticket) => ticket.value,
        decode: Ticket.new,
      );

      await store.write(const Ticket('abc'));
      final read = await store.read();

      expect(read?.value, 'abc');
    });

    test('reads back nothing once cleared', () async {
      final store = StoredCredential<Ticket>(
        MemoryKeyValueStore(),
        key: 'ticket',
        encode: (ticket) => ticket.value,
        decode: Ticket.new,
      );
      await store.write(const Ticket('abc'));

      await store.clear();

      expect(await store.read(), isNull);
    });

    test(
      'reads back nothing when the stored shape no longer decodes',
      () async {
        final store = StoredCredential<Ticket>(
          MemoryKeyValueStore(const {'ticket': 'abc'}),
          key: 'ticket',
          encode: (ticket) => ticket.value,
          decode: (raw) => throw const FormatException('changed shape'),
        );

        expect(await store.read(), isNull);
      },
    );
  });
}
