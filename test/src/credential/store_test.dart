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

class Ticket {
  final String value;

  const Ticket(this.value);
}

Future<void> _boot() async {
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
    directory = await Directory.systemTemp.createTemp('pylon_storage');
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

  group('StoredCredential', () {
    StoredCredential<Ticket> storeOver(
      String key, {
      String Function(Ticket)? encode,
      Ticket Function(String)? decode,
    }) => StoredCredential<Ticket>(
      SecureStorage.string_(key, ''),
      encode: encode ?? (ticket) => ticket.value,
      decode: decode ?? Ticket.new,
    );

    test('reads back a credential through the encoding it was given', () async {
      await _boot();
      final store = storeOver('ticket');

      await store.write(const Ticket('abc'));
      final read = await store.read();

      expect(read?.value, 'abc');
    });

    test('keeps the credential in the vault and never in the preferences', () async {
      await _boot();
      final store = storeOver('ticket');

      await store.write(const Ticket('abc'));

      expect(await const FlutterSecureStorage().read(key: 'ticket'), 'abc');
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    });

    test('finds at the next launch what was written before', () async {
      await _boot();
      await storeOver('ticket').write(const Ticket('abc'));

      await _boot();

      expect((await storeOver('ticket').read())?.value, 'abc');
    });

    test('reads back nothing once cleared', () async {
      await _boot();
      final store = storeOver('ticket');
      await store.write(const Ticket('abc'));

      await store.clear();

      expect(await store.read(), isNull);
      expect(await const FlutterSecureStorage().read(key: 'ticket'), isNull);
    });

    test('reads back nothing when the stored shape no longer decodes', () async {
      FlutterSecureStorage.setMockInitialValues({'ticket': 'abc'});
      await _boot();
      final store = storeOver('ticket', decode: (raw) => throw const FormatException('changed shape'));

      expect(await store.read(), isNull);
    });
  });
}
