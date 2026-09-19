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

import 'package:fiber_pylon/di/di.dart';
import 'package:fiber_pylon/fiber_pylon.dart' hide Database;
import 'package:fiber_pylon/src/storage/secure_storage.dart' show SecretStore, hkdfSha256;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart' hide Database;

/// A vault held in memory that counts what is done to it.
final class MemoryStore implements SecretStore {
  MemoryStore([Map<String, String>? initial]) : values = {...?initial};

  final Map<String, String> values;
  int reads = 0;
  int writes = 0;
  int deletes = 0;

  @override
  Future<String?> read(String name) async {
    reads++;
    return values[name];
  }

  @override
  Future<Map<String, String>> readAll() async {
    reads++;
    return {...values};
  }

  @override
  Future<void> write(String name, String value) async {
    writes++;
    values[name] = value;
  }

  @override
  Future<void> delete(String name) async {
    deletes++;
    values.remove(name);
  }
}

final class FailingReadStore extends MemoryStore {
  @override
  Future<Map<String, String>> readAll() async => throw StateError('the vault is locked');
}

/// Says it wrote, and keeps something else.
final class ForgetfulStore extends MemoryStore {
  @override
  Future<void> write(String name, String value) async {
    writes++;
    values[name] = 'not what was written';
  }
}

/// Refuses every write once it has been told to.
final class RefusingStore extends MemoryStore {
  bool refuse = false;

  @override
  Future<void> write(String name, String value) async {
    if (refuse) throw StateError('the vault refuses');
    return super.write(name, value);
  }
}

final class RecordingReporter implements Reporter {
  final List<Object> errors = [];

  @override
  void log(String message) {}

  @override
  void recordError(
    Object error,
    StackTrace? stackTrace, {
    bool fatal = false,
    Map<String, Object?> context = const {},
  }) => errors.add(error);

  @override
  void identify(String? identifier) {}
}

String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int> _bytes(String hex) => [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];

Future<Fingerprint> _fingerprintOf(SecretStore store, {Random? random}) async =>
    (await SecureStorage.load(store: store, random: random)).loadedFingerprint;

void main() {
  group('SecureStorage.load, for the fingerprint', () {
    test('creates a fingerprint the first time and keeps it', () async {
      final store = MemoryStore();

      final fingerprint = await _fingerprintOf(store);

      expect(store.writes, 1);
      final kept = store.values[SecureStorage.fingerprintName]!;
      expect(base64Url.decode(kept), hasLength(32));
      expect(fingerprint, isNotNull);
    });

    test('gives the same fingerprint every time after, without writing again', () async {
      final store = MemoryStore();
      final first = await _fingerprintOf(store);

      final second = await _fingerprintOf(store);

      expect(second.matches(first), isTrue);
      expect(store.writes, 1);
    });

    test('creates one only, when two loads race', () async {
      final store = MemoryStore();

      final both = await Future.wait([SecureStorage.load(store: store), SecureStorage.load(store: store)]);

      expect(store.writes, 1);
      expect(both[0].loadedFingerprint.matches(both[1].loadedFingerprint), isTrue);
    });

    test('gives two different installations two different fingerprints', () async {
      final a = await _fingerprintOf(MemoryStore());
      final b = await _fingerprintOf(MemoryStore());

      expect(a.matches(b), isFalse);
    });

    test('takes its bytes from the random source it is given', () async {
      final a = await _fingerprintOf(MemoryStore(), random: Random(7));
      final b = await _fingerprintOf(MemoryStore(), random: Random(7));

      expect(a.matches(b), isTrue);
    });

    test('refuses a record that is not a fingerprint, and leaves it alone', () async {
      for (final bad in ['not base64 at all!!', base64Url.encode(List.filled(16, 1)), '']) {
        final store = MemoryStore({SecureStorage.fingerprintName: bad});

        await expectLater(SecureStorage.load(store: store), throwsA(isA<FingerprintError>()));

        expect(store.writes, 0, reason: 'a bad record must not be replaced');
        expect(store.values[SecureStorage.fingerprintName], bad);
      }
    });

    test('never reads a failing vault as an empty one', () async {
      final store = FailingReadStore();

      await expectLater(SecureStorage.load(store: store), throwsStateError);

      expect(store.writes, 0);
    });

    test('refuses a vault that does not give back what it was given', () async {
      await expectLater(SecureStorage.load(store: ForgetfulStore()), throwsA(isA<FingerprintError>()));
    });

    test('a failed load can be tried again', () async {
      final store = ForgetfulStore();
      await expectLater(SecureStorage.load(store: store), throwsA(isA<FingerprintError>()));
      store.values.clear();

      await expectLater(SecureStorage.load(store: store), throwsA(isA<FingerprintError>()));
      expect(store.writes, 2);
    });
  });

  group('derive', () {
    test('always gives the same bytes for the same purpose', () async {
      final fingerprint = await _fingerprintOf(MemoryStore());

      expect(fingerprint.derive('database'), fingerprint.derive('database'));
    });

    test('gives unrelated bytes for two purposes', () async {
      final fingerprint = await _fingerprintOf(MemoryStore());

      expect(fingerprint.derive('database'), isNot(fingerprint.derive('other')));
    });

    test('gives unrelated bytes for two fingerprints', () async {
      final a = await _fingerprintOf(MemoryStore());
      final b = await _fingerprintOf(MemoryStore());

      expect(a.derive('database'), isNot(b.derive('database')));
    });

    test('gives the length asked for, as bytes and as hex', () async {
      final fingerprint = await _fingerprintOf(MemoryStore());

      expect(fingerprint.derive('x'), hasLength(32));
      expect(fingerprint.derive('x', length: 64), hasLength(64));
      expect(fingerprint.deriveHex('x'), hasLength(64));
      expect(fingerprint.deriveHex('x', length: 16), hasLength(32));
      expect(fingerprint.deriveHex('x'), matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('a longer derivation starts with the shorter one', () async {
      final fingerprint = await _fingerprintOf(MemoryStore());

      expect(fingerprint.derive('x', length: 64).sublist(0, 32), fingerprint.derive('x', length: 32));
    });

    test('refuses an empty purpose', () async {
      final fingerprint = await _fingerprintOf(MemoryStore());

      expect(() => fingerprint.derive(''), throwsArgumentError);
    });

    test('forgets the secret once disposed', () async {
      final fingerprint = await _fingerprintOf(MemoryStore());
      final before = fingerprint.derive('database');

      fingerprint.dispose();

      expect(fingerprint.derive('database'), isNot(before));
    });

    test('answers Uint8List', () async {
      final fingerprint = await _fingerprintOf(MemoryStore());

      expect(fingerprint.derive('x'), isA<Uint8List>());
    });
  });

  group('matches', () {
    test('is true for the same fingerprint and false for another', () async {
      final store = MemoryStore();
      final a = await _fingerprintOf(store);
      final again = await _fingerprintOf(store);

      expect(a.matches(again), isTrue);
      expect(a.matches(Fingerprint.generate()), isFalse);
    });
  });

  group('what it shows', () {
    test('never prints the secret', () async {
      final store = MemoryStore();
      final fingerprint = await _fingerprintOf(store);
      final secret = store.values[SecureStorage.fingerprintName]!;

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

  group('the entries, registered by configureSdk', () {
    late MemoryStore vault;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      PackageInfo.setMockInitialValues(
        appName: 'pylon_secure',
        packageName: 'dev.fiber.secure',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      AppStorage.encryption = EncryptionPolicy.off;
      FlutterSecureStorage.setMockInitialValues({});
      await GetIt.instance.reset();
      vault = MemoryStore();
    });

    tearDown(() => GetIt.instance.reset());

    /// Registers a [SecureStorage] over [vault] the way `configureSdk` would.
    Future<void> register() async =>
        GetIt.instance.registerSingleton<SecureStorage>(await SecureStorage.load(store: vault));

    test('read what the vault held when it was loaded', () async {
      vault.values['token'] = 'abc';
      vault.values['tries'] = '3';
      vault.values['enabled'] = 'true';
      vault.values['pin'] = base64Url.encode([1, 2, 3]);
      await register();

      expect(SecureStorage.string_('token', '')(), 'abc');
      expect(SecureStorage.int_('tries', 0)(), 3);
      expect(SecureStorage.bool_('enabled', false)(), isTrue);
      expect(SecureStorage.bytes_('pin', Uint8List(0))(), [1, 2, 3]);
    });

    test('answer the default for a key nothing has written to', () async {
      await register();

      expect(SecureStorage.string_('token', 'none')(), 'none');
      expect(SecureStorage.int_('tries', 7)(), 7);
      expect(SecureStorage.bool_('enabled', true)(), isTrue);
      expect(SecureStorage.bytes_('pin', Uint8List.fromList([9]))(), [9]);
    });

    test('write to the vault first, then change and tell their listeners', () async {
      await register();
      final token = SecureStorage.string_('token', '');
      final seen = <String>[];
      final subscription = token.stream.listen(seen.add);

      await token.set('abc');
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(vault.values['token'], 'abc');
      expect(token.value, 'abc');
      expect(seen, ['', 'abc']);
    });

    test('round trip every type through the vault', () async {
      await register();
      final bytes = SecureStorage.bytes_('pin', Uint8List(0));
      final tries = SecureStorage.int_('tries', 0);
      final enabled = SecureStorage.bool_('enabled', false);

      await bytes.set(Uint8List.fromList([4, 5, 6]));
      await tries.set(-12);
      await enabled.set(true);

      expect(vault.values['tries'], '-12');
      expect(vault.values['enabled'], 'true');
      expect(base64Url.decode(vault.values['pin']!), [4, 5, 6]);
      final again = await SecureStorage.load(store: vault);
      expect(again.loadedFingerprint.matches(SecureStorage.fingerprint), isTrue);
    });

    test('keep what a later launch will read', () async {
      await register();
      await SecureStorage.string_('token', '').set('kept');
      await GetIt.instance.reset();

      await register();

      expect(SecureStorage.string_('token', '')(), 'kept');
    });

    test('forget the vault\'s value on clear, and answer the default', () async {
      await register();
      final token = SecureStorage.string_('token', 'none');
      await token.set('abc');

      await token.clear();

      expect(vault.values.containsKey('token'), isFalse);
      expect(token.value, 'none');
      expect(vault.deletes, 1);
    });

    test('write nothing for a value that is already the current one', () async {
      await register();
      final token = SecureStorage.string_('token', '');
      await token.set('abc');
      final writes = vault.writes;

      await token.set('abc');
      await SecureStorage.bytes_('pin', Uint8List.fromList([1])).set(Uint8List.fromList([1]));

      expect(vault.writes, writes);
    });

    test('are left as they were when the vault refuses a write', () async {
      final refusing = RefusingStore();
      GetIt.instance.registerSingleton<SecureStorage>(await SecureStorage.load(store: refusing));
      final token = SecureStorage.string_('token', 'none');
      final seen = <String>[];
      final subscription = token.stream.listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      refusing.refuse = true;

      await expectLater(token.set('abc'), throwsStateError);
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(token.value, 'none');
      expect(seen, ['none']);
      expect(refusing.values.containsKey('token'), isFalse);
    });

    test('report a stored value that no longer decodes, and answer the default', () async {
      vault.values['tries'] = 'many';
      vault.values['enabled'] = 'perhaps';
      vault.values['pin'] = '!!!';
      await register();
      final reporter = RecordingReporter();

      expect(SecureStorage.int_('tries', 1, reporter: reporter)(), 1);
      expect(SecureStorage.bool_('enabled', true, reporter: reporter)(), isTrue);
      expect(SecureStorage.bytes_('pin', Uint8List.fromList([2]), reporter: reporter)(), [2]);
      expect(reporter.errors, hasLength(3));
    });

    test('refuse the keys the package keeps for itself, and an empty one', () async {
      await register();

      expect(() => SecureStorage.string_(SecureStorage.fingerprintName, ''), throwsArgumentError);
      expect(() => SecureStorage.string_('pylon.anything', ''), throwsArgumentError);
      expect(() => SecureStorage.string_('', ''), throwsArgumentError);
    });

    test('never expose the fingerprint as an entry', () async {
      await register();

      expect(vault.values.containsKey(SecureStorage.fingerprintName), isTrue);
      expect(SecureStorage.string_('token', 'x')(), 'x');
      expect(SecureStorage.fingerprint.toString(), 'Fingerprint(hidden)');
    });

    test('are resolved by configureSdk before the app database', () async {
      FlutterSecureStorage.setMockInitialValues({'token': 'from the vault'});
      await GetIt.instance.reset();

      await configureSdk();

      expect(SecureStorage.string_('token', '')(), 'from the vault');
      expect(AppStorage.isEncrypted, isFalse);
      expect(SecureStorage.fingerprint.matches(SecureStorage.fingerprint), isTrue);
    });
  });
}
