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

import 'dart:io';

import 'package:fiber_pylon/di/di.dart';
import 'package:fiber_pylon/fiber_pylon.dart';
import 'package:fiber_pylon/src/credential/store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

enum HouseSignal { rejected, unreachable }

const String _vaultKey = 'pylon.credential.v1';

Credential credentialLasting(Duration lifetime, {String token = 'first', String? refreshToken = 'again'}) =>
    Credential(token: token, refreshToken: refreshToken, expiresAt: DateTime.now().add(lifetime), holder: 'ada');

Future<void> hold([Credential? credential]) async {
  await GetIt.instance.reset();
  GetIt.instance.registerSingleton<Credentials>(
    await Credentials.forTesting(MemoryCredentialStore<Credential>(credential)),
    dispose: (credentials) => credentials.dispose(),
  );
}

Future<void> launch() async {
  await GetIt.instance.reset();
  await configureSdk();
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pylon_credentials');
    databaseFactoryFfi.setDatabasesPath(directory.path);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    LocalDatabase.encryption = EncryptionPolicy.off;
    PackageInfo.setMockInitialValues(
      appName: 'pylon_test',
      packageName: 'dev.fiber.pylon_test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  tearDown(() async {
    await GetIt.instance.reset();
    await directory.delete(recursive: true);
  });

  group('Credentials', () {
    test('holds nothing until a credential is set', () async {
      await hold();

      expect(Credentials.isHeld, isFalse);
      expect(Credentials.value, isNull);
      expect(Credentials.held.value, isFalse);
    });

    test('holds the credential it was given', () async {
      await hold();
      final credential = credentialLasting(const Duration(hours: 1));

      await Credentials.set(credential);

      expect(Credentials.value, same(credential));
      expect(Credentials.isHeld, isTrue);
      expect(Credentials.held.value, isTrue);
    });

    test('forgets the credential once cleared', () async {
      await hold(credentialLasting(const Duration(hours: 1)));

      await Credentials.clear();

      expect(Credentials.value, isNull);
      expect(Credentials.isHeld, isFalse);
    });

    test('gives a new listener the credential in force, then each one that replaces it', () async {
      final first = credentialLasting(const Duration(hours: 1), token: 'first');
      final second = credentialLasting(const Duration(hours: 1), token: 'second');
      await hold(first);
      final seen = <Credential?>[];
      Credentials.stream.listen(seen.add);

      await Credentials.set(second);
      await Credentials.clear();
      await pumpEventQueue();

      expect(seen, [first, second, null]);
    });

    test('follows the same through values as through stream', () async {
      await hold();
      final viaStream = <Credential?>[];
      final viaValues = <Credential?>[];
      Credentials.stream.listen(viaStream.add);
      Credentials.values.listen(viaValues.add);

      await Credentials.set(credentialLasting(const Duration(hours: 1)));
      await pumpEventQueue();

      expect(viaValues, viaStream);
    });

    test('moves held only on a sign-in and a sign-out', () async {
      await hold();
      final seen = <bool>[];
      Credentials.held.values.listen(seen.add);

      await Credentials.set(credentialLasting(const Duration(hours: 1), token: 'one'));
      await Credentials.set(credentialLasting(const Duration(hours: 1), token: 'two'));
      await Credentials.clear();
      await pumpEventQueue();

      expect(seen, [false, true, false]);
    });

    test('is stale within minutes of expiry and not before', () async {
      await hold();
      expect(Credentials.isStale, isFalse);

      await Credentials.set(credentialLasting(const Duration(hours: 1)));
      expect(Credentials.isStale, isFalse);

      await Credentials.set(credentialLasting(const Duration(minutes: 2)));
      expect(Credentials.isStale, isTrue);
    });

    test('is never stale for a credential that does not expire', () async {
      await hold(const Credential(token: 'forever', refreshToken: 'again'));

      expect(Credentials.isStale, isFalse);
    });

    test('renews a credential restored stale as soon as the exchange is plugged in', () async {
      await hold(credentialLasting(const Duration(minutes: -1), token: 'expired'));
      final renewed = credentialLasting(const Duration(hours: 1), token: 'renewed');
      final asked = <Credential>[];

      Credentials.renewWith(
        refresh: (current) async {
          asked.add(current);
          return renewed;
        },
        fatalSignals: const {HouseSignal.rejected},
      );
      await pumpEventQueue();

      expect(asked.single.token, 'expired');
      expect(Credentials.value, same(renewed));
    });

    test('renews on demand and hands the exchange the credential in force', () async {
      final first = credentialLasting(const Duration(hours: 1), token: 'first');
      final second = credentialLasting(const Duration(hours: 1), token: 'second');
      await hold(first);
      Credentials.renewWith(refresh: (current) async => second, fatalSignals: const {HouseSignal.rejected});

      await Credentials.renew();

      expect(Credentials.value, same(second));
    });

    test('never renews a credential that carries no refresh token', () async {
      await hold(credentialLasting(const Duration(minutes: 2), refreshToken: null));
      var asked = 0;
      Credentials.renewWith(
        refresh: (current) async {
          asked++;
          return current;
        },
        fatalSignals: const {HouseSignal.rejected},
      );

      await Credentials.renew();
      await Credentials.ensureFresh();

      expect(asked, 0);
    });

    test('never renews before the exchange is plugged in', () async {
      final stored = credentialLasting(const Duration(minutes: 2));
      await hold(stored);

      await Credentials.renew();
      await Credentials.ensureFresh();

      expect(Credentials.value, same(stored));
    });

    test('clears the credential when the backend rejects it', () async {
      await hold(credentialLasting(const Duration(minutes: 2)));
      Credentials.renewWith(
        refresh: (current) async => throw const Fault<HouseSignal>(HouseSignal.rejected),
        fatalSignals: const {HouseSignal.rejected},
      );

      await Credentials.renew();

      expect(Credentials.isHeld, isFalse);
    });

    test('keeps the credential when the backend is only unreachable', () async {
      final stored = credentialLasting(const Duration(minutes: 2));
      await hold(stored);
      Credentials.renewWith(
        refresh: (current) async => throw const Fault<HouseSignal>(HouseSignal.unreachable),
        fatalSignals: const {HouseSignal.rejected},
      );

      await Credentials.renew();

      expect(Credentials.value, same(stored));
    });

    test('replaces the exchange and its fatal signals when plugged in again', () async {
      await hold(credentialLasting(const Duration(minutes: 2)));
      Credentials.renewWith(
        refresh: (current) async => throw const Fault<HouseSignal>(HouseSignal.rejected),
        fatalSignals: const {HouseSignal.rejected},
      );
      Credentials.renewWith(
        refresh: (current) async => throw const Fault<HouseSignal>(HouseSignal.rejected),
        fatalSignals: const {HouseSignal.unreachable},
      );

      await Credentials.renew();

      expect(Credentials.isHeld, isTrue);
    });
  });

  group('Credentials in the vault', () {
    test('is found again at the next launch', () async {
      await launch();
      final credential = credentialLasting(const Duration(hours: 1));
      await Credentials.set(credential);

      await launch();

      expect(Credentials.value, credential);
      expect(Credentials.isHeld, isTrue);
    });

    test('is not found again once cleared', () async {
      await launch();
      await Credentials.set(credentialLasting(const Duration(hours: 1)));
      await Credentials.clear();

      await launch();

      expect(Credentials.isHeld, isFalse);
    });

    test('is kept in the vault under a key of the package and never in the preferences', () async {
      await launch();

      await Credentials.set(credentialLasting(const Duration(hours: 1), token: 'secret-token'));

      expect(await const FlutterSecureStorage().read(key: _vaultKey), contains('secret-token'));
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    });

    test('reads as nothing held when the vault holds something that is not a credential', () async {
      FlutterSecureStorage.setMockInitialValues({_vaultKey: 'not a credential'});

      await launch();

      expect(Credentials.isHeld, isFalse);
    });

    test('cannot be declared as a project entry', () async {
      await launch();

      expect(() => SecureStorage.string_(_vaultKey, ''), throwsArgumentError);
    });
  });
}
