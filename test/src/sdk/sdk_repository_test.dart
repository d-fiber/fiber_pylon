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

import 'package:fiber_pylon/fiber_pylon.dart';
import 'package:fiber_pylon/src/credential/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

enum HouseSignal { unauthorized, noRoute, unknown }

enum HouseError { signedOut, unknown }

final class Shelf extends SdkRepository<List<int>, List<int>, HouseError, HouseSignal> {
  Shelf({this.authenticated = false, super.health, List<int> stored = const []})
    : stored = [...stored],
      super(initial: const [], offlineSignals: const {HouseSignal.noRoute});

  final bool authenticated;
  final List<int> stored;
  final StreamController<List<int>> _changes = StreamController<List<int>>.broadcast();

  List<int> answer = [1, 2, 3];
  Object? failure;
  Completer<List<int>>? gate;
  int fetches = 0;
  int watches = 0;

  @override
  bool get isAuthenticated => authenticated;

  @override
  Stream<List<int>> watchLocal() {
    watches++;
    return Stream<List<int>>.multi((controller) {
      controller.add([...stored]);
      final subscription = _changes.stream.listen(controller.add);
      controller.onCancel = subscription.cancel;
    });
  }

  @override
  Future<List<int>> fetch() async {
    fetches++;
    final held = gate;
    if (held != null) return held.future;
    final broken = failure;
    if (broken != null) throw broken;
    return answer;
  }

  @override
  Future<void> response(List<int> response) async {
    stored
      ..clear()
      ..addAll(response);
    _changes.add([...stored]);
  }

  @override
  HouseError resolve(Fault<HouseSignal> fault) =>
      fault.signal == HouseSignal.unauthorized ? HouseError.signedOut : HouseError.unknown;
}

Future<void> hold([Credential? credential]) async {
  await GetIt.instance.reset();
  GetIt.instance.registerSingleton<Credentials>(
    await Credentials.forTesting(MemoryCredentialStore<Credential>(credential)),
    dispose: (credentials) => credentials.dispose(),
  );
}

void main() {
  setUp(() => GetIt.instance.reset());

  tearDown(() => GetIt.instance.reset());

  group('SdkRepository reading', () {
    test('reads as its initial value until the database has answered', () async {
      final shelf = Shelf(stored: [7]);

      expect(shelf.value, isEmpty);

      await pumpEventQueue();

      expect(shelf.value, [7]);
      await shelf.dispose();
    });

    test('does not read the database until it is asked to', () async {
      final shelf = Shelf();
      expect(shelf.watches, 0);

      shelf.value;
      shelf.stream;
      shelf();

      expect(shelf.watches, 1);
      await shelf.dispose();
    });

    test('reads the same through a call as through value', () async {
      final shelf = Shelf(stored: [7]);
      await pumpEventQueue();

      expect(shelf(), shelf.value);
      await shelf.dispose();
    });

    test('gives a new listener the initial value, then what the database holds and each change', () async {
      final shelf = Shelf(stored: [7]);
      final seen = <List<int>>[];
      shelf.stream.listen(seen.add);
      await pumpEventQueue();

      await shelf.refresh();
      await pumpEventQueue();

      expect(seen.first, isEmpty);
      expect(seen[1], [7]);
      expect(seen.last, [1, 2, 3]);
      await shelf.dispose();
    });

    test('follows the same through values as through stream', () async {
      final shelf = Shelf();
      final viaStream = <List<int>>[];
      final viaValues = <List<int>>[];
      shelf.stream.listen(viaStream.add);
      shelf.values.listen(viaValues.add);

      await shelf.refresh();
      await pumpEventQueue();

      expect(viaValues, viaStream);
      await shelf.dispose();
    });

    test('keeps reading what is stored when a refresh fails', () async {
      final shelf = Shelf(stored: [7])..failure = const Fault<HouseSignal>(HouseSignal.unknown);
      shelf.value;
      await pumpEventQueue();

      await shelf.refresh();
      await pumpEventQueue();

      expect(shelf.value, [7]);
      await shelf.dispose();
    });
  });

  group('SdkRepository refresh', () {
    test('writes what the network answered, which moves the value', () async {
      final shelf = Shelf();
      shelf.value;

      final status = await shelf.refresh();
      await pumpEventQueue();

      expect(status, const StatusSucceeded<HouseError>());
      expect(shelf.value, [1, 2, 3]);
      await shelf.dispose();
    });

    test('joins a refresh that is already under way', () async {
      final shelf = Shelf()..gate = Completer<List<int>>();

      final first = shelf.refresh();
      final second = shelf.refresh();
      shelf.gate!.complete([4]);

      expect(await first, const StatusSucceeded<HouseError>());
      expect(await second, const StatusSucceeded<HouseError>());
      expect(shelf.fetches, 1);
      await shelf.dispose();
    });

    test('asks again once the previous refresh has finished', () async {
      final shelf = Shelf();

      await shelf.refresh();
      await shelf.refresh();

      expect(shelf.fetches, 2);
      await shelf.dispose();
    });

    test('ends offline for a signal it was told means the network is out of reach', () async {
      final shelf = Shelf()..failure = const Fault<HouseSignal>(HouseSignal.noRoute);

      expect(await shelf.refresh(), const StatusOffline<HouseError>());
      await shelf.dispose();
    });

    test('ends failed with the project error for any other signal', () async {
      final shelf = Shelf()..failure = const Fault<HouseSignal>(HouseSignal.unauthorized);

      expect(await shelf.refresh(), const StatusFailed<HouseError>(HouseError.signedOut));
      await shelf.dispose();
    });

    test('takes a fault of another adapter for a bug and lets it propagate', () async {
      final shelf = Shelf()..failure = const Fault<String>('elsewhere');

      await expectLater(shelf.refresh(), throwsA(isA<Fault<String>>()));
      expect(shelf.status.value, const StatusIdle<HouseError>());
      await shelf.dispose();
    });

    test('lets an error that is not a fault propagate and goes back to idle', () async {
      final shelf = Shelf()..failure = StateError('a bug');

      await expectLater(shelf.refresh(), throwsStateError);

      expect(shelf.status.value, const StatusIdle<HouseError>());
      shelf.failure = null;
      expect(await shelf.refresh(), const StatusSucceeded<HouseError>());
      await shelf.dispose();
    });

    test('makes no request while the health monitor says the network is out', () async {
      final health = HealthMonitor(name: 'network', initial: false);
      final shelf = Shelf(health: health);

      expect(await shelf.refresh(), const StatusOffline<HouseError>());
      expect(shelf.fetches, 0);

      health.report(healthy: true);
      expect(await shelf.refresh(), const StatusSucceeded<HouseError>());
      await shelf.dispose();
      await health.dispose();
    });

    test('makes no request for an authenticated call while no credential is held', () async {
      await hold();
      final shelf = Shelf(authenticated: true);

      expect(await shelf.refresh(), const StatusUnauthenticated<HouseError>());
      expect(shelf.fetches, 0);

      await Credentials.set(const Credential(token: 'abc'));
      expect(await shelf.refresh(), const StatusSucceeded<HouseError>());
      await shelf.dispose();
    });

    test('never asks for a credential on a call that does not carry one', () async {
      final shelf = Shelf();

      expect(await shelf.refresh(), const StatusSucceeded<HouseError>());
      await shelf.dispose();
    });
  });

  group('SdkRepository status', () {
    test('is idle until a refresh has run', () async {
      final shelf = Shelf();

      expect(shelf.status.value, const StatusIdle<HouseError>());
      await shelf.dispose();
    });

    test('goes from running to succeeded, and stays there', () async {
      final shelf = Shelf();
      final seen = <Status<HouseError>>[];
      shelf.status.values.listen(seen.add);

      await shelf.refresh();
      await pumpEventQueue();

      expect(seen, const [StatusIdle<HouseError>(), StatusRunning<HouseError>(), StatusSucceeded<HouseError>()]);
      expect(shelf.status.value, const StatusSucceeded<HouseError>());
      await shelf.dispose();
    });

    test('reports running while the network is being asked', () async {
      final shelf = Shelf()..gate = Completer<List<int>>();

      final refreshing = shelf.refresh();
      await pumpEventQueue();
      expect(shelf.status.value, const StatusRunning<HouseError>());

      shelf.gate!.complete([1]);
      await refreshing;
      await shelf.dispose();
    });

    test('carries the project error of a failure until the next refresh', () async {
      final shelf = Shelf()..failure = const Fault<HouseSignal>(HouseSignal.unknown);

      await shelf.refresh();
      expect(shelf.status.value, const StatusFailed<HouseError>(HouseError.unknown));

      shelf.failure = null;
      await shelf.refresh();
      expect(shelf.status.value, const StatusSucceeded<HouseError>());
      await shelf.dispose();
    });

    test('does not repeat a status it already holds', () async {
      final shelf = Shelf()..failure = const Fault<HouseSignal>(HouseSignal.noRoute);
      await shelf.refresh();
      final seen = <Status<HouseError>>[];
      shelf.status.stream.skip(1).listen(seen.add);

      await shelf.refresh();
      await pumpEventQueue();

      expect(seen, const [StatusRunning<HouseError>(), StatusOffline<HouseError>()]);
      await shelf.dispose();
    });
  });

  group('SdkRepository disposal', () {
    test('does nothing once disposed and answers the status it had', () async {
      final shelf = Shelf();
      await shelf.refresh();
      await shelf.dispose();

      final status = await shelf.refresh();

      expect(status, const StatusSucceeded<HouseError>());
      expect(shelf.fetches, 1);
    });

    test('keeps the last value readable and stops following the database', () async {
      final shelf = Shelf(stored: [7]);
      await pumpEventQueue();
      shelf.value;
      await pumpEventQueue();

      await shelf.dispose();
      shelf.stored.add(8);
      shelf._changes.add([7, 8]);
      await pumpEventQueue();

      expect(shelf.value, [7]);
    });

    test('closes the streams it handed out', () async {
      final shelf = Shelf();
      final done = shelf.stream.toList();
      final statusDone = shelf.status.stream.toList();

      await shelf.dispose();

      await expectLater(done, completes);
      await expectLater(statusDone, completes);
    });

    test('can be disposed before it was ever read', () async {
      final shelf = Shelf();

      await shelf.dispose();

      expect(shelf.value, isEmpty);
      expect(shelf.watches, 0);
    });
  });
}
