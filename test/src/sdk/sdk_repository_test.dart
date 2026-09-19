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
  Shelf({
    this.authenticated = false,
    this.observes = false,
    this.readFails = false,
    this.holdsNothing = false,
    List<int> stored = const [],
  }) : stored = [...stored],
       super(offlineSignals: const {HouseSignal.noRoute});

  final bool authenticated;
  final bool observes;
  final bool readFails;
  final bool holdsNothing;
  final List<int> stored;
  final StreamController<List<int>?> _changes = StreamController<List<int>?>.broadcast();

  List<int> answer = [1, 2, 3];
  Object? failure;
  Completer<List<int>>? gate;
  int fetches = 0;
  int watches = 0;

  @override
  bool get isAuthenticated => authenticated;

  @override
  bool get observesConnection => observes;

  @override
  Stream<List<int>?> stream() {
    watches++;
    return Stream<List<int>?>.multi((controller) {
      if (readFails) {
        controller.addError(StateError('the database failed'));
      } else {
        controller.add(holdsNothing ? null : [...stored]);
      }
      final subscription = _changes.stream.listen(controller.add, onError: controller.addError);
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

Future<void> connect({required bool reachable}) async {
  await GetIt.instance.reset();
  GetIt.instance.registerSingleton<Network>(
    await Network.forTesting(reachable: reachable),
    dispose: (network) => network.dispose(),
  );
}

Future<void> hold([Credential? credential]) async {
  await GetIt.instance.reset();
  GetIt.instance.registerSingleton<Credentials>(
    await Credentials.forTesting(MemoryCredentialStore<Credential>(credential)),
    dispose: (credentials) => credentials.dispose(),
  );
}

Future<List<Status<HouseError>>> watching(Shelf shelf) async {
  final seen = <Status<HouseError>>[];
  shelf.status.stream.listen(seen.add);
  await pumpEventQueue();
  seen.clear();
  return seen;
}

void main() {
  setUp(() => GetIt.instance.reset());

  tearDown(() => GetIt.instance.reset());

  group('SdkRepository reading', () {
    test('holds nothing until the database has answered', () async {
      final shelf = Shelf(stored: [7]);

      expect(shelf.data.value, isNull);

      await pumpEventQueue();

      expect(shelf.data.value, [7]);
      await shelf.dispose();
    });

    test('starts listening to the database right after it is made, without being asked', () async {
      final shelf = Shelf(stored: [7]);
      expect(shelf.watches, 0);

      await pumpEventQueue();

      expect(shelf.watches, 1);
      expect(shelf.data.value, [7]);
      await shelf.dispose();
    });

    test('listens to the database once, however it is reached', () async {
      final shelf = Shelf();

      shelf.data;
      shelf.data.value;
      shelf.status;
      unawaited(shelf.refresh());
      await pumpEventQueue();

      expect(shelf.watches, 1);
      await shelf.dispose();
    });

    test('has the stored value already for a screen that asks later', () async {
      final shelf = Shelf(stored: [7]);
      await pumpEventQueue();
      final seen = <List<int>?>[];

      shelf.data.stream.listen(seen.add);
      await pumpEventQueue();

      expect(shelf.data.value, [7]);
      expect(seen, [
        [7],
      ]);
      await shelf.dispose();
    });

    test('holds nothing, and says the read went through, when the database holds nothing', () async {
      final shelf = Shelf(holdsNothing: true);
      final seen = <Status<HouseError>>[];
      shelf.status.stream.listen(seen.add);

      await pumpEventQueue();

      expect(shelf.data.value, isNull);
      expect(seen, const [StatusRunning<HouseError>(), StatusSucceeded<HouseError>(), StatusIdle<HouseError>()]);
      await shelf.dispose();
    });

    test('gives a new listener what the database holds, then each change', () async {
      final shelf = Shelf(stored: [7]);
      await pumpEventQueue();
      final seen = <List<int>?>[];
      shelf.data.stream.listen(seen.add);
      await pumpEventQueue();

      await shelf.refresh();
      await pumpEventQueue();

      expect(seen.first, [7]);
      expect(seen.last, [1, 2, 3]);
      await shelf.dispose();
    });

    test('gives a screen that asks within the first moments nothing, then the stored value', () async {
      final shelf = Shelf(stored: [7]);
      final seen = <List<int>?>[];

      shelf.data.stream.listen(seen.add);
      await pumpEventQueue();

      expect(seen, [
        null,
        [7],
      ]);
      await shelf.dispose();
    });

    test('hands an error of the database stream to whoever follows data, and keeps the value', () async {
      final shelf = Shelf(stored: [7]);
      final errors = <Object>[];
      shelf.data.stream.listen((_) {}, onError: errors.add);
      await pumpEventQueue();

      shelf._changes.addError(StateError('the database failed'));
      await pumpEventQueue();

      expect(errors.single, isA<StateError>());
      expect(shelf.data.value, [7]);
      await shelf.dispose();
    });

    test('keeps reading what is stored when a refresh fails', () async {
      final shelf = Shelf(stored: [7])..failure = const Fault<HouseSignal>(HouseSignal.unknown);
      shelf.data.value;
      await pumpEventQueue();

      await shelf.refresh();
      await pumpEventQueue();

      expect(shelf.data.value, [7]);
      await shelf.dispose();
    });
  });

  group('SdkRepository refresh', () {
    test('writes what the network answered, which moves the value', () async {
      final shelf = Shelf();
      shelf.data.value;

      final status = await shelf.refresh();
      await pumpEventQueue();

      expect(status, const StatusSucceeded<HouseError>());
      expect(shelf.data.value, [1, 2, 3]);
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

    test('makes no request while the device has no connection, once it observes the connection', () async {
      await connect(reachable: false);
      final shelf = Shelf(observes: true);

      expect(await shelf.refresh(), const StatusOffline<HouseError>());
      expect(shelf.fetches, 0);
      await shelf.dispose();
    });

    test('asks again as soon as the connection is back', () async {
      final changes = StreamController<bool>();
      await GetIt.instance.reset();
      GetIt.instance.registerSingleton<Network>(
        await Network.forTesting(reachable: false, changes: changes.stream),
        dispose: (network) => network.dispose(),
      );
      final shelf = Shelf(observes: true);
      expect(await shelf.refresh(), const StatusOffline<HouseError>());

      changes.add(true);
      await pumpEventQueue();

      expect(await shelf.refresh(), const StatusSucceeded<HouseError>());
      expect(shelf.fetches, 1);
      await shelf.dispose();
      await changes.close();
    });

    test('tries the request without a connection when it does not observe the connection', () async {
      await connect(reachable: false);
      final shelf = Shelf();

      expect(await shelf.refresh(), const StatusSucceeded<HouseError>());
      expect(shelf.fetches, 1);
      await shelf.dispose();
    });

    test('ends offline on its own signal even when it does not observe the connection', () async {
      await connect(reachable: false);
      final shelf = Shelf()..failure = const Fault<HouseSignal>(HouseSignal.noRoute);

      expect(await shelf.refresh(), const StatusOffline<HouseError>());
      expect(shelf.fetches, 1);
      await shelf.dispose();
    });

    test('never asks the network state of a repository that does not observe it', () async {
      final shelf = Shelf();

      expect(await shelf.refresh(), const StatusSucceeded<HouseError>());
      await shelf.dispose();
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
    test('starts loading what the database holds', () async {
      final shelf = Shelf();

      expect(shelf.status.value, const StatusRunning<HouseError>());
      await shelf.dispose();
    });

    test('announces the first load once, then goes idle', () async {
      final shelf = Shelf(stored: [7]);
      final seen = <Status<HouseError>>[];
      shelf.status.stream.listen(seen.add);

      await pumpEventQueue();

      expect(seen, const [StatusRunning<HouseError>(), StatusSucceeded<HouseError>(), StatusIdle<HouseError>()]);
      expect(shelf.status.value, const StatusIdle<HouseError>());
      await shelf.dispose();
    });

    test('says nothing of the first load while a refresh is under way, and waits for it', () async {
      final shelf = Shelf()..gate = Completer<List<int>>();
      final seen = <Status<HouseError>>[];
      shelf.status.stream.listen(seen.add);

      final refreshing = shelf.refresh();
      await pumpEventQueue();
      expect(seen, const [StatusRunning<HouseError>()]);

      shelf.gate!.complete([1]);
      await refreshing;
      await pumpEventQueue();

      expect(seen, const [StatusRunning<HouseError>(), StatusSucceeded<HouseError>(), StatusIdle<HouseError>()]);
      await shelf.dispose();
    });

    test('goes back to idle when the database fails the first read', () async {
      final shelf = Shelf(readFails: true);
      final errors = <Object>[];
      shelf.data.stream.listen((_) {}, onError: errors.add);

      await pumpEventQueue();

      expect(errors.single, isA<StateError>());
      expect(shelf.status.value, const StatusIdle<HouseError>());
      await shelf.dispose();
    });

    test('announces the success of a refresh once, then goes back to idle', () async {
      final shelf = Shelf();
      final seen = await watching(shelf);

      await shelf.refresh();
      await pumpEventQueue();

      expect(seen, const [StatusRunning<HouseError>(), StatusSucceeded<HouseError>(), StatusIdle<HouseError>()]);
      expect(shelf.status.value, const StatusIdle<HouseError>());
      await shelf.dispose();
    });

    test('stays running until the network has answered, and only then announces the outcome', () async {
      final shelf = Shelf()..gate = Completer<List<int>>();
      final seen = await watching(shelf);

      final refreshing = shelf.refresh();
      await pumpEventQueue();
      expect(shelf.status.value, const StatusRunning<HouseError>());
      expect(seen, const [StatusRunning<HouseError>()]);

      shelf.gate!.complete([1]);
      await refreshing;
      await pumpEventQueue();

      expect(seen, const [StatusRunning<HouseError>(), StatusSucceeded<HouseError>(), StatusIdle<HouseError>()]);
      await shelf.dispose();
    });

    test('announces a failure with the project error, then goes back to idle', () async {
      final shelf = Shelf()..failure = const Fault<HouseSignal>(HouseSignal.unknown);
      final seen = await watching(shelf);

      await shelf.refresh();
      await pumpEventQueue();

      expect(seen, const [
        StatusRunning<HouseError>(),
        StatusFailed<HouseError>(HouseError.unknown),
        StatusIdle<HouseError>(),
      ]);
      await shelf.dispose();
    });

    test('announces the same failure again when the next refresh fails the same way', () async {
      final shelf = Shelf()..failure = const Fault<HouseSignal>(HouseSignal.unknown);
      final seen = await watching(shelf);

      await shelf.refresh();
      await shelf.refresh();
      await pumpEventQueue();

      expect(seen.whereType<StatusFailed<HouseError>>(), hasLength(2));
      await shelf.dispose();
    });

    test('announces that no credential was held, then goes back to idle', () async {
      await hold();
      final shelf = Shelf(authenticated: true);
      final seen = await watching(shelf);

      await shelf.refresh();
      await pumpEventQueue();

      expect(seen, const [StatusRunning<HouseError>(), StatusUnauthenticated<HouseError>(), StatusIdle<HouseError>()]);
      await shelf.dispose();
    });
  });

  group('SdkRepository offline status', () {
    Future<StreamController<bool>> reachability({required bool reachable}) async {
      final changes = StreamController<bool>.broadcast();
      await GetIt.instance.reset();
      GetIt.instance.registerSingleton<Network>(
        await Network.forTesting(reachable: reachable, changes: changes.stream),
        dispose: (network) => network.dispose(),
      );
      addTearDown(changes.close);
      return changes;
    }

    test('stays offline while the connection is out, and goes idle when it is back', () async {
      final changes = await reachability(reachable: false);
      final shelf = Shelf(observes: true);
      await pumpEventQueue();

      await shelf.refresh();
      await pumpEventQueue();
      expect(shelf.status.value, const StatusOffline<HouseError>());

      changes.add(true);
      await pumpEventQueue();

      expect(shelf.status.value, const StatusIdle<HouseError>());
      await shelf.dispose();
    });

    test('answers a refresh at once, without a request or a change, while it stays offline', () async {
      await reachability(reachable: false);
      final shelf = Shelf(observes: true);
      await shelf.refresh();
      final seen = await watching(shelf);

      final status = await shelf.refresh();
      await pumpEventQueue();

      expect(status, const StatusOffline<HouseError>());
      expect(shelf.fetches, 0);
      expect(seen, isEmpty);
      await shelf.dispose();
    });

    test(
      'stays offline after a request that failed on its own signal, until the connection drops and returns',
      () async {
        final changes = await reachability(reachable: true);
        final shelf = Shelf(observes: true)..failure = const Fault<HouseSignal>(HouseSignal.noRoute);
        await shelf.refresh();
        await pumpEventQueue();
        expect(shelf.status.value, const StatusOffline<HouseError>());

        changes.add(false);
        await pumpEventQueue();
        expect(shelf.status.value, const StatusOffline<HouseError>());

        changes.add(true);
        await pumpEventQueue();

        expect(shelf.status.value, const StatusIdle<HouseError>());
        await shelf.dispose();
      },
    );

    test('tries again when the connection is not what kept it offline', () async {
      await reachability(reachable: true);
      final shelf = Shelf(observes: true)..failure = const Fault<HouseSignal>(HouseSignal.noRoute);
      await shelf.refresh();
      shelf.failure = null;

      final status = await shelf.refresh();

      expect(status, const StatusSucceeded<HouseError>());
      expect(shelf.fetches, 2);
      await shelf.dispose();
    });

    test('announces offline once and goes idle when it does not observe the connection', () async {
      await reachability(reachable: false);
      final shelf = Shelf()..failure = const Fault<HouseSignal>(HouseSignal.noRoute);
      final seen = await watching(shelf);

      await shelf.refresh();
      await pumpEventQueue();

      expect(seen, const [StatusRunning<HouseError>(), StatusOffline<HouseError>(), StatusIdle<HouseError>()]);
      expect(shelf.status.value, const StatusIdle<HouseError>());
      await shelf.dispose();
    });
  });

  group('SdkRepository disposal', () {
    test('does nothing once disposed and answers the status it had', () async {
      final shelf = Shelf();
      await shelf.refresh();
      await shelf.dispose();

      final status = await shelf.refresh();

      expect(status, const StatusIdle<HouseError>());
      expect(shelf.fetches, 1);
    });

    test('keeps the last value readable and stops following the database', () async {
      final shelf = Shelf(stored: [7]);
      await pumpEventQueue();
      shelf.data.value;
      await pumpEventQueue();

      await shelf.dispose();
      shelf.stored.add(8);
      shelf._changes.add([7, 8]);
      await pumpEventQueue();

      expect(shelf.data.value, [7]);
    });

    test('closes the streams it handed out', () async {
      final shelf = Shelf();
      final done = shelf.data.stream.toList();
      final statusDone = shelf.status.stream.toList();

      await shelf.dispose();

      await expectLater(done, completes);
      await expectLater(statusDone, completes);
    });

    test('can be disposed before it started listening', () async {
      final shelf = Shelf();

      await shelf.dispose();

      expect(shelf.data.value, isNull);
      expect(shelf.watches, 0);
    });
  });
}
