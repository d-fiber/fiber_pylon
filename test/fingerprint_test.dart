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

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:fiber_pylon/src/security/fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';

/// A vault held in memory that counts what is done to it.
final class MemoryStore implements SecretStore {
  MemoryStore([Map<String, String>? initial]) : values = {...?initial};

  final Map<String, String> values;
  int reads = 0;
  int writes = 0;

  @override
  Future<String?> read(String name) async {
    reads++;
    return values[name];
  }

  @override
  Future<void> write(String name, String value) async {
    writes++;
    values[name] = value;
  }
}

final class FailingReadStore extends MemoryStore {
  @override
  Future<String?> read(String name) async => throw StateError('the vault is locked');
}

/// Says it wrote, and keeps something else.
final class ForgetfulStore extends MemoryStore {
  @override
  Future<void> write(String name, String value) async {
    writes++;
    values[name] = 'not what was written';
  }
}

String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int> _bytes(String hex) => [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];

void main() {
  group('Fingerprint.load', () {
    test('creates a fingerprint the first time and keeps it', () async {
      final store = MemoryStore();

      final fingerprint = await Fingerprint.load(store: store);

      expect(store.writes, 1);
      final kept = store.values[Fingerprint.storedName]!;
      expect(base64Url.decode(kept), hasLength(32));
      expect(fingerprint, isNotNull);
    });

    test('gives the same fingerprint every time after, without writing again', () async {
      final store = MemoryStore();
      final first = await Fingerprint.load(store: store);

      final second = await Fingerprint.load(store: store);

      expect(second.matches(first), isTrue);
      expect(store.writes, 1);
    });

    test('creates one only, when two loads race', () async {
      final store = MemoryStore();

      final both = await Future.wait([Fingerprint.load(store: store), Fingerprint.load(store: store)]);

      expect(store.writes, 1);
      expect(both[0].matches(both[1]), isTrue);
    });

    test('gives two different installations two different fingerprints', () async {
      final a = await Fingerprint.load(store: MemoryStore());
      final b = await Fingerprint.load(store: MemoryStore());

      expect(a.matches(b), isFalse);
    });

    test('takes its bytes from the random source it is given', () async {
      final a = await Fingerprint.load(store: MemoryStore(), random: Random(7));
      final b = await Fingerprint.load(store: MemoryStore(), random: Random(7));

      expect(a.matches(b), isTrue);
    });

    test('refuses a record that is not a fingerprint, and leaves it alone', () async {
      for (final bad in ['not base64 at all!!', base64Url.encode(List.filled(16, 1)), '']) {
        final store = MemoryStore({Fingerprint.storedName: bad});

        await expectLater(Fingerprint.load(store: store), throwsA(isA<FingerprintError>()));

        expect(store.writes, 0, reason: 'a bad record must not be replaced');
        expect(store.values[Fingerprint.storedName], bad);
      }
    });

    test('never reads a failing vault as an empty one', () async {
      final store = FailingReadStore();

      await expectLater(Fingerprint.load(store: store), throwsStateError);

      expect(store.writes, 0);
    });

    test('refuses a vault that does not give back what it was given', () async {
      await expectLater(Fingerprint.load(store: ForgetfulStore()), throwsA(isA<FingerprintError>()));
    });

    test('a failed load can be tried again', () async {
      final store = ForgetfulStore();
      await expectLater(Fingerprint.load(store: store), throwsA(isA<FingerprintError>()));
      store.values.clear();

      await expectLater(Fingerprint.load(store: store), throwsA(isA<FingerprintError>()));
      expect(store.writes, 2);
    });
  });

  group('derive', () {
    test('always gives the same bytes for the same purpose', () async {
      final fingerprint = await Fingerprint.load(store: MemoryStore());

      expect(fingerprint.derive('database'), fingerprint.derive('database'));
    });

    test('gives unrelated bytes for two purposes', () async {
      final fingerprint = await Fingerprint.load(store: MemoryStore());

      expect(fingerprint.derive('database'), isNot(fingerprint.derive('other')));
    });

    test('gives unrelated bytes for two fingerprints', () async {
      final a = await Fingerprint.load(store: MemoryStore());
      final b = await Fingerprint.load(store: MemoryStore());

      expect(a.derive('database'), isNot(b.derive('database')));
    });

    test('gives the length asked for, as bytes and as hex', () async {
      final fingerprint = await Fingerprint.load(store: MemoryStore());

      expect(fingerprint.derive('x'), hasLength(32));
      expect(fingerprint.derive('x', length: 64), hasLength(64));
      expect(fingerprint.deriveHex('x'), hasLength(64));
      expect(fingerprint.deriveHex('x', length: 16), hasLength(32));
      expect(fingerprint.deriveHex('x'), matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('a longer derivation starts with the shorter one', () async {
      final fingerprint = await Fingerprint.load(store: MemoryStore());

      expect(fingerprint.derive('x', length: 64).sublist(0, 32), fingerprint.derive('x', length: 32));
    });

    test('refuses an empty purpose', () async {
      final fingerprint = await Fingerprint.load(store: MemoryStore());

      expect(() => fingerprint.derive(''), throwsArgumentError);
    });

    test('forgets the secret once disposed', () async {
      final fingerprint = await Fingerprint.load(store: MemoryStore());
      final before = fingerprint.derive('database');

      fingerprint.dispose();

      expect(fingerprint.derive('database'), isNot(before));
    });
  });

  group('matches', () {
    test('is true for the same fingerprint and false for another', () async {
      final store = MemoryStore();
      final a = await Fingerprint.load(store: store);
      final again = await Fingerprint.load(store: store);
      final other = Fingerprint.generate();

      expect(a.matches(again), isTrue);
      expect(a.matches(other), isFalse);
    });
  });

  group('what it shows', () {
    test('never prints the secret', () async {
      final store = MemoryStore();
      final fingerprint = await Fingerprint.load(store: store);
      final secret = store.values[Fingerprint.storedName]!;

      expect(fingerprint.toString(), 'Fingerprint(hidden)');
      expect('$fingerprint', isNot(contains(secret)));
    });

    test('generate makes 256 bits from the secure source', () {
      final a = Fingerprint.generate();
      final b = Fingerprint.generate();

      expect(a.matches(b), isFalse);
      expect(a.derive('x', length: 32), isNot(everyElement(0)));
    });
  });

  group('hkdfSha256 against RFC 5869', () {
    test('test case 1', () {
      final okm = hkdfSha256(
        List.filled(22, 0x0b),
        salt: _bytes('000102030405060708090a0b0c'),
        info: _bytes('f0f1f2f3f4f5f6f7f8f9'),
        length: 42,
      );

      expect(_hex(okm), '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865');
    });

    test('test case 3, with no salt and no info', () {
      final okm = hkdfSha256(List.filled(22, 0x0b), length: 42);

      expect(_hex(okm), '8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8');
    });

    test('refuses a length it cannot give', () {
      expect(() => hkdfSha256([1], length: 0), throwsRangeError);
      expect(() => hkdfSha256([1], length: 255 * 32 + 1), throwsRangeError);
    });
  });

  test('Uint8List is what derive answers', () async {
    final fingerprint = await Fingerprint.load(store: MemoryStore());

    expect(fingerprint.derive('x'), isA<Uint8List>());
  });
}
