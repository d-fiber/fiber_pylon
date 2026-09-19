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
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

class Ticket {
  final String value;

  const Ticket(this.value);
}

Future<ValkeryStorage> _preferences() async {
  await GetIt.instance.reset();
  await configureSdk();
  return GetIt.instance<ValkeryStorage>();
}

Future<_AppPreferences> _appPreferences() async {
  await _preferences();
  return _AppPreferences();
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
    test('reads back a credential through the encoding it was given', () async {
      final preferences = await _preferences();
      final store = StoredCredential<Ticket>(
        preferences,
        key: 'ticket',
        encode: (ticket) => ticket.value,
        decode: Ticket.new,
      );

      await store.write(const Ticket('abc'));
      final read = await store.read();

      expect(read?.value, 'abc');
    });

    test('reads back nothing once cleared', () async {
      final preferences = await _preferences();
      final store = StoredCredential<Ticket>(
        preferences,
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
        SharedPreferences.setMockInitialValues({'ticket': 'abc'});
        final preferences = await _preferences();
        final store = StoredCredential<Ticket>(
          preferences,
          key: 'ticket',
          encode: (ticket) => ticket.value,
          decode: (raw) => throw const FormatException('changed shape'),
        );

        expect(await store.read(), isNull);
      },
    );
  });

  group('ValkeryStorage', () {
    test(
      'every entry answers its default value before anything is written',
      () async {
        final prefs = await _appPreferences();

        expect(prefs.volume.value, 50);
        expect(prefs.enabled.value, isFalse);
        expect(prefs.ratio.value, 1.0);
        expect(prefs.label.value, 'default');
        expect(prefs.mood.value, Mood.neutral);
        expect(prefs.profile.value.name, 'anonymous');
      },
    );

    test('reads back each native type through the shared_preferences getter '
        'matching it', () async {
      final prefs = await _appPreferences();

      await prefs.volume.set(80);
      await prefs.enabled.set(true);
      await prefs.ratio.set(2.5);
      await prefs.label.set('changed');

      expect(prefs.volume.value, 80);
      expect(prefs.enabled.value, isTrue);
      expect(prefs.ratio.value, 2.5);
      expect(prefs.label.value, 'changed');
    });

    test('stores an enum by name rather than by index', () async {
      final prefs = await _appPreferences();

      await prefs.mood.set(Mood.happy);

      final rawPrefs = await SharedPreferences.getInstance();
      expect(rawPrefs.getString('mood'), 'happy');
      expect(prefs.mood.value, Mood.happy);
    });

    test(
      'answers the fallback for a stored enum value that no longer matches',
      () async {
        SharedPreferences.setMockInitialValues({'mood': 'furious'});
        final prefs = await _appPreferences();

        expect(prefs.mood.value, Mood.neutral);
      },
    );

    test('reads back a JSON-encoded value', () async {
      final prefs = await _appPreferences();

      await prefs.profile.set(const _Profile(name: 'Alex'));

      expect(prefs.profile.value.name, 'Alex');
    });

    test(
      'answers the fallback for a stored JSON value that no longer decodes',
      () async {
        SharedPreferences.setMockInitialValues({'profile': 'not json'});
        final prefs = await _appPreferences();

        expect(prefs.profile.value.name, 'anonymous');
      },
    );

    test('reads back a JSON-encoded list of a native type', () async {
      final prefs = await _appPreferences();

      await prefs.scores.set([3, 1, 4]);

      expect(prefs.scores.value, [3, 1, 4]);
    });

    test('reads back a JSON-encoded list of a custom type', () async {
      final prefs = await _appPreferences();

      await prefs.crew.set(const [_Profile(name: 'Alex'), _Profile(name: 'Sam')]);

      expect(prefs.crew.value.map((profile) => profile.name), ['Alex', 'Sam']);
    });

    test(
      'answers the fallback for a stored JSON list that no longer decodes',
      () async {
        SharedPreferences.setMockInitialValues({'scores': 'not json'});
        final prefs = await _appPreferences();

        expect(prefs.scores.value, isEmpty);
      },
    );

    test('publishes every value it is given', () async {
      final prefs = await _appPreferences();
      final seen = <int>[];
      prefs.volume.stream.listen(seen.add);

      await prefs.volume.set(10);
      await prefs.volume.set(20);
      await pumpEventQueue();

      // 50 first: stream is backed by a BehaviorSubject, which replays the
      // current value to a new listener before anything that changes after.
      expect(seen, [50, 10, 20]);
      await prefs.volume.dispose();
    });

    test('clear resets to the default value and publishes it', () async {
      final prefs = await _appPreferences();
      await prefs.volume.set(99);

      await prefs.volume.clear();

      expect(prefs.volume.value, 50);
    });
  });
}

enum Mood { happy, sad, neutral }

class _AppPreferences {
  late final volume = ValkeryStorage.int_('volume', 50);
  late final enabled = ValkeryStorage.bool_('enabled', false);
  late final ratio = ValkeryStorage.double_('ratio', 1.0);
  late final label = ValkeryStorage.string_('label', 'default');
  late final mood = ValkeryStorage.enum_('mood', Mood.values, Mood.neutral);
  late final profile = ValkeryStorage.json_(
    'profile',
    const _Profile(name: 'anonymous'),
    _Profile.fromJson,
  );
  late final scores = ValkeryStorage.list_<int>('scores', const [], (json) => json as int);
  late final crew = ValkeryStorage.list_<_Profile>(
    'crew',
    const [],
    (json) => _Profile.fromJson(json as Map<String, dynamic>),
    toJson: (profile) => profile.toJson(),
  );
}

class _Profile implements ValkeryJson {
  final String name;

  const _Profile({required this.name});

  factory _Profile.fromJson(Map<String, dynamic> json) =>
      _Profile(name: json['name'] as String);

  @override
  Map<String, dynamic> toJson() => {'name': name};
}
