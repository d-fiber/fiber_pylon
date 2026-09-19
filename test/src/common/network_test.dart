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

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fiber_pylon/fiber_pylon.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

Future<StreamController<bool>> follow({required bool reachable}) async {
  final changes = StreamController<bool>.broadcast();
  await GetIt.instance.reset();
  GetIt.instance.registerSingleton<Network>(
    await Network.forTesting(reachable: reachable, changes: changes.stream),
    dispose: (network) => network.dispose(),
  );
  addTearDown(changes.close);
  return changes;
}

void main() {
  setUp(() => GetIt.instance.reset());

  tearDown(() => GetIt.instance.reset());

  group('Network', () {
    test('is reachable when the device starts with a connection', () async {
      await follow(reachable: true);

      expect(Network.isReachable.value, isTrue);
    });

    test('is not reachable when the device starts without one', () async {
      await follow(reachable: false);

      expect(Network.isReachable.value, isFalse);
    });

    test('follows the connection coming and going', () async {
      final changes = await follow(reachable: true);
      final seen = <bool>[];
      Network.isReachable.stream.listen(seen.add);

      changes.add(false);
      changes.add(true);
      await pumpEventQueue();

      expect(seen, [true, false, true]);
      expect(Network.isReachable.value, isTrue);
    });

    test('does not wake a listener for a connection that did not change', () async {
      final changes = await follow(reachable: true);
      final seen = <bool>[];
      Network.isReachable.stream.skip(1).listen(seen.add);

      changes.add(true);
      changes.add(true);
      await pumpEventQueue();

      expect(seen, isEmpty);
    });

    test('ignores an error from the operating system and keeps what it knew', () async {
      final changes = await follow(reachable: false);

      changes.addError(StateError('the platform failed'));
      await pumpEventQueue();

      expect(Network.isReachable.value, isFalse);
    });

    test('stops following once disposed, and keeps its last answer', () async {
      final changes = await follow(reachable: true);

      await GetIt.instance.reset();

      changes.add(false);
      await pumpEventQueue();
      expect(changes.hasListener, isFalse);
    });

    test('is reachable when the platform cannot say', () async {
      final network = await Network.initialize();
      GetIt.instance.registerSingleton<Network>(network, dispose: (network) => network.dispose());

      expect(Network.isReachable.value, isTrue);
    });
  });

  group('Network.reads', () {
    test('reads any interface that is up as a connection', () {
      for (final result in ConnectivityResult.values.where((result) => result != ConnectivityResult.none)) {
        expect(Network.reads([result]), isTrue, reason: '$result');
      }
    });

    test('reads none as no connection', () {
      expect(Network.reads([ConnectivityResult.none]), isFalse);
    });

    test('reads an empty report as no connection', () {
      expect(Network.reads(const []), isFalse);
    });

    test('reads a connection listed beside none as a connection', () {
      expect(Network.reads([ConnectivityResult.none, ConnectivityResult.wifi]), isTrue);
    });
  });
}
