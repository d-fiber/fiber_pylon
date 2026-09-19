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
import 'dart:typed_data';

import 'package:fiber_pylon/di/di.dart';
import 'package:fiber_pylon/fiber_pylon.dart' hide Database;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart' hide Database;

const _fingerprintName = 'pylon.fingerprint.v1';

/// A vault held in memory that counts what is done to it, and can be made to
/// fail, refuse or forget.
final class FakeVault extends FlutterSecureStoragePlatform {
  FakeVault([Map<String, String>? initial]) : data = {...?initial};

  final Map<String, String> data;
  int writes = 0;
  int deletes = 0;
  bool failReads = false;
  bool refuseWrites = false;
  bool forgetWrites = false;

  @override
  Future<bool> containsKey({required String key, required Map<String, String> options}) async => data.containsKey(key);

  @override
  Future<void> delete({required String key, required Map<String, String> options}) async {
    deletes++;
    data.remove(key);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async => data.clear();

  @override
  Future<String?> read({required String key, required Map<String, String> options}) async => data[key];

  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) async {
    if (failReads) throw StateError('the vault is locked');
    return {...data};
  }

  @override
  Future<void> write({required String key, required String value, required Map<String, String> options}) async {
    if (refuseWrites) throw StateError('the vault refuses');
    writes++;
    data[key] = forgetWrites ? 'not what was written' : value;
  }
}

String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// The fingerprint whose secret is the bytes 0 to 31, so that what is derived
/// from it can be checked against another implementation of HKDF.
final String _knownSecret = base64Url.encode(List.generate(32, (i) => i));

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'pylon_secure',
      packageName: 'dev.fiber.secure',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    LocalDatabase.encryption = EncryptionPolicy.off;
    await GetIt.instance.reset();
  });

  tearDown(() => GetIt.instance.reset());

  /// Starts [SecureStorage] over [vault] the way `configureSdk` would, and
  /// registers it.
  Future<void> boot(FakeVault vault) async {
    FlutterSecureStoragePlatform.instance = vault;
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<SecureStorage>(
      await SecureStorage.initialize(),
      dispose: (storage) => storage.dispose(),
    );
  }

  group('initialize, for the fingerprint', () {
    test('creates a fingerprint the first time and keeps it', () async {
      final vault = FakeVault();

      await boot(vault);

      expect(vault.writes, 1);
      expect(base64Url.decode(vault.data[_fingerprintName]!), hasLength(32));
    });

    test('finds the same fingerprint at the next launch, without writing again', () async {
      final vault = FakeVault();
      await boot(vault);
      final first = SecureStorage.fingerprint.derive('database');

      await boot(vault);

      expect(SecureStorage.fingerprint.derive('database'), first);
      expect(vault.writes, 1);
    });

    test('gives two installations two different fingerprints', () async {
      await boot(FakeVault());
      final a = SecureStorage.fingerprint.derive('database');

      await boot(FakeVault());

      expect(SecureStorage.fingerprint.derive('database'), isNot(a));
    });

    test('refuses a record that is not a fingerprint, and leaves it alone', () async {
      for (final bad in ['not base64 at all!!', base64Url.encode(List.filled(16, 1)), '']) {
        final vault = FakeVault({_fingerprintName: bad});
        FlutterSecureStoragePlatform.instance = vault;

        await expectLater(SecureStorage.initialize(), throwsStateError);

        expect(vault.writes, 0, reason: 'a bad record must not be replaced');
        expect(vault.data[_fingerprintName], bad);
      }
    });

    test('never reads a failing vault as an empty one', () async {
      final vault = FakeVault()..failReads = true;
      FlutterSecureStoragePlatform.instance = vault;

      await expectLater(SecureStorage.initialize(), throwsStateError);

      expect(vault.writes, 0);
    });

    test('refuses a vault that does not give back what it was given', () async {
      final vault = FakeVault()..forgetWrites = true;
      FlutterSecureStoragePlatform.instance = vault;

      await expectLater(SecureStorage.initialize(), throwsStateError);
    });

    test('a failed start can be tried again', () async {
      final vault = FakeVault()..forgetWrites = true;
      FlutterSecureStoragePlatform.instance = vault;
      await expectLater(SecureStorage.initialize(), throwsStateError);
      vault
        ..forgetWrites = false
        ..data.clear();

      await SecureStorage.initialize();

      expect(vault.data[_fingerprintName], isNotNull);
    });
  });

  group('the fingerprint', () {
    setUp(() => boot(FakeVault({_fingerprintName: _knownSecret})));

    test('derives what another implementation of HKDF derives', () {
      final fingerprint = SecureStorage.fingerprint;

      expect(_hex(fingerprint.derive('database')), 'e32038a6b0be347cd626559948dedfe5ba261882aab9a68d1ba1477f3e417155');
      expect(
        _hex(fingerprint.derive('database', length: 64)),
        'e32038a6b0be347cd626559948dedfe5ba261882aab9a68d1ba1477f3e4171555b9da9c5c44c2c78f50ebb92e39b2eaf12a56ce1a606fe69e0eb6b7017a2537e',
      );
      expect(_hex(fingerprint.derive('other')), '9ea14e103b02ea9f3208d3ebb350d045cb76d680ae2159c843cb443d5ec65658');
    });

    test('always gives the same bytes for the same purpose, and unrelated ones for two', () {
      final fingerprint = SecureStorage.fingerprint;

      expect(fingerprint.derive('a'), fingerprint.derive('a'));
      expect(fingerprint.derive('a'), isNot(fingerprint.derive('b')));
      expect(fingerprint.derive('x', length: 64).sublist(0, 32), fingerprint.derive('x', length: 32));
      expect(fingerprint.derive('x'), isA<Uint8List>());
    });

    test('refuses an empty purpose and a length it cannot give', () {
      final fingerprint = SecureStorage.fingerprint;

      expect(() => fingerprint.derive(''), throwsArgumentError);
      expect(() => fingerprint.derive('x', length: 0), throwsRangeError);
      expect(() => fingerprint.derive('x', length: 255 * 32 + 1), throwsRangeError);
    });

    test('is the same as itself, and not the same as another', () {
      final fingerprint = SecureStorage.fingerprint;

      expect(fingerprint.matches(fingerprint), isTrue);
      expect(fingerprint.matches(Fingerprint.generate()), isFalse);
      expect(Fingerprint.generate().matches(Fingerprint.generate()), isFalse);
    });

    test('never prints the secret', () {
      expect(SecureStorage.fingerprint.toString(), 'Fingerprint(hidden)');
      expect('${SecureStorage.fingerprint}', isNot(contains(_knownSecret)));
    });

    test('is wiped from memory when the storage is let go of', () async {
      final fingerprint = SecureStorage.fingerprint;
      final before = fingerprint.derive('database');

      await GetIt.instance.reset();

      expect(fingerprint.derive('database'), isNot(before));
    });

    test('is not an entry: no entry can be declared on its key', () {
      expect(() => SecureStorage.string_(_fingerprintName, ''), throwsArgumentError);
    });
  });

  group('the entries', () {
    late FakeVault vault;

    setUp(() async {
      vault = FakeVault();
      await boot(vault);
    });

    test('read what the vault held when it was loaded', () async {
      vault
        ..data['token'] = 'abc'
        ..data['tries'] = '3'
        ..data['enabled'] = 'true'
        ..data['pin'] = base64Url.encode([1, 2, 3]);
      await boot(vault);

      expect(SecureStorage.string_('token', '')(), 'abc');
      expect(SecureStorage.int_('tries', 0)(), 3);
      expect(SecureStorage.bool_('enabled', false)(), isTrue);
      expect(SecureStorage.bytes_('pin', Uint8List(0))(), [1, 2, 3]);
    });

    test('answer the default for a key nothing has written to', () {
      expect(SecureStorage.string_('token', 'none')(), 'none');
      expect(SecureStorage.int_('tries', 7)(), 7);
      expect(SecureStorage.bool_('enabled', true)(), isTrue);
      expect(SecureStorage.bytes_('pin', Uint8List.fromList([9]))(), [9]);
    });

    test('write to the vault first, then change and tell their listeners', () async {
      final token = SecureStorage.string_('token', '');
      final seen = <String>[];
      final subscription = token.stream.listen(seen.add);

      await token.set('abc');
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(vault.data['token'], 'abc');
      expect(token.value, 'abc');
      expect(seen, ['', 'abc']);
    });

    test('round trip every type through the vault', () async {
      await SecureStorage.bytes_('pin', Uint8List(0)).set(Uint8List.fromList([4, 5, 6]));
      await SecureStorage.int_('tries', 0).set(-12);
      await SecureStorage.bool_('enabled', false).set(true);

      expect(vault.data['tries'], '-12');
      expect(vault.data['enabled'], 'true');
      expect(base64Url.decode(vault.data['pin']!), [4, 5, 6]);
    });

    test('keep what a later launch will read', () async {
      await SecureStorage.string_('token', '').set('kept');

      await boot(vault);

      expect(SecureStorage.string_('token', '')(), 'kept');
    });

    test('forget the vault\'s value on clear, and answer the default', () async {
      final token = SecureStorage.string_('token', 'none');
      await token.set('abc');

      await token.clear();

      expect(vault.data.containsKey('token'), isFalse);
      expect(token.value, 'none');
      expect(vault.deletes, 1);
    });

    test('write nothing for a value that is already the current one', () async {
      final token = SecureStorage.string_('token', '');
      final pin = SecureStorage.bytes_('pin', Uint8List.fromList([1]));
      await token.set('abc');
      await pin.set(Uint8List.fromList([2]));
      final writes = vault.writes;

      await token.set('abc');
      await pin.set(Uint8List.fromList([2]));
      await SecureStorage.string_('token', '').set('abc');

      expect(vault.writes, writes);
    });

    test('are left as they were when the vault refuses a write', () async {
      final token = SecureStorage.string_('token', 'none');
      final seen = <String>[];
      final subscription = token.stream.listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      vault.refuseWrites = true;

      await expectLater(token.set('abc'), throwsStateError);
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(token.value, 'none');
      expect(seen, ['none']);
      expect(vault.data.containsKey('token'), isFalse);
    });

    test('answer the default for a stored value that no longer decodes', () async {
      vault
        ..data['tries'] = 'many'
        ..data['enabled'] = 'perhaps'
        ..data['pin'] = '!!!';
      await boot(vault);

      expect(SecureStorage.int_('tries', 1)(), 1);
      expect(SecureStorage.bool_('enabled', true)(), isTrue);
      expect(SecureStorage.bytes_('pin', Uint8List.fromList([2]))(), [2]);
    });

    test('refuse the keys the package keeps for itself, and an empty one', () {
      expect(() => SecureStorage.string_('pylon.anything', ''), throwsArgumentError);
      expect(() => SecureStorage.string_('', ''), throwsArgumentError);
    });
  });

  group('configureSdk', () {
    test('resolves it before the app database, so the entries are ready', () async {
      FlutterSecureStorage.setMockInitialValues({'token': 'from the vault'});

      await configureSdk();

      expect(SecureStorage.string_('token', '')(), 'from the vault');
      expect(LocalDatabase.isEncrypted, isFalse);
    });
  });
}
