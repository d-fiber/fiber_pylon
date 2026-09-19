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

import 'package:flutter_test/flutter_test.dart';
import 'package:fiber_pylon/fiber_pylon.dart';

enum HouseSignal { stale, rejected, missing, duplicate }

class Ticket {
  final String value;
  final DateTime expiresAt;

  const Ticket(this.value, this.expiresAt);
}

class CountingRefresher implements CredentialRefresher<Ticket> {
  final bool succeeds;
  int callCount = 0;

  CountingRefresher({this.succeeds = true});

  @override
  Future<Ticket> refresh(Ticket current) async {
    callCount++;
    if (!succeeds) return current;
    return Ticket(
      'renewed-$callCount',
      DateTime.now().add(const Duration(hours: 1)),
    );
  }
}

CredentialManager<Ticket, HouseSignal> managerFor(
  CredentialRefresher<Ticket> refresher, {
  Duration lifetime = const Duration(hours: 1),
}) => CredentialManager<Ticket, HouseSignal>(
  store: MemoryCredentialStore<Ticket>(
    Ticket('first', DateTime.now().add(lifetime)),
  ),
  refresher: refresher,
  expiresAt: (ticket) => ticket.expiresAt,
  fatalSignals: const {HouseSignal.rejected},
);

CallGuard<HouseSignal> guardFor(
  CredentialManager<Ticket, HouseSignal> manager,
) => CallGuard<HouseSignal>.renewing(
  duplicateSignal: HouseSignal.duplicate,
  credentials: manager,
  renewOn: const {HouseSignal.stale},
);

void main() {
  group('CallGuard', () {
    test('returns what the call produced', () async {
      final guard = CallGuard<HouseSignal>(
        duplicateSignal: HouseSignal.duplicate,
      );

      expect(await guard.run(() async => 'answer'), 'answer');
    });

    test('refuses a second call sharing a key with one in flight', () async {
      final guard = CallGuard<HouseSignal>(
        duplicateSignal: HouseSignal.duplicate,
      );
      final blocked = Completer<int>();

      final first = guard.run(() => blocked.future, dedupKey: 'read');
      await pumpEventQueue();

      await expectLater(
        guard.run(() async => 2, dedupKey: 'read'),
        throwsA(
          isA<Fault<HouseSignal>>().having(
            (fault) => fault.signal,
            'signal',
            HouseSignal.duplicate,
          ),
        ),
      );

      blocked.complete(1);
      expect(await first, 1);
    });

    test('allows the key again once the call has finished', () async {
      final guard = CallGuard<HouseSignal>(
        duplicateSignal: HouseSignal.duplicate,
      );

      await guard.run(() async => 1, dedupKey: 'read');

      expect(await guard.run(() async => 2, dedupKey: 'read'), 2);
      expect(guard.isInFlight('read'), isFalse);
    });

    test('lets calls without a key overlap', () async {
      final guard = CallGuard<HouseSignal>(
        duplicateSignal: HouseSignal.duplicate,
      );
      final blocked = Completer<int>();

      final first = guard.run(() => blocked.future);
      final second = guard.run(() async => 2);

      expect(await second, 2);
      blocked.complete(1);
      expect(await first, 1);
    });

    test('renews the credential before an authenticated call', () async {
      final refresher = CountingRefresher();
      final manager = managerFor(
        refresher,
        lifetime: const Duration(minutes: 1),
      );
      await manager.start();
      final guard = guardFor(manager);

      await guard.run(() async => 'ok');

      expect(refresher.callCount, 1);
      await manager.dispose();
    });

    test(
      'replays a call once after renewing on a signal it was given',
      () async {
        final refresher = CountingRefresher();
        final manager = managerFor(refresher);
        await manager.start();
        final guard = guardFor(manager);
        var attempts = 0;

        final answer = await guard.run(() async {
          attempts++;
          if (attempts == 1) throw const Fault(HouseSignal.stale);
          return 'ok';
        });

        expect(answer, 'ok');
        expect(attempts, 2);
        expect(refresher.callCount, 1);
        await manager.dispose();
      },
    );

    test('does not replay when renewal produced the same credential', () async {
      final manager = managerFor(CountingRefresher(succeeds: false));
      await manager.start();
      final guard = guardFor(manager);
      var attempts = 0;

      await expectLater(
        guard.run(() async {
          attempts++;
          throw const Fault(HouseSignal.stale);
        }),
        throwsA(isA<Fault<HouseSignal>>()),
      );

      expect(attempts, 1);
      await manager.dispose();
    });

    test('revokes when the replay fails on the same signal', () async {
      final manager = managerFor(CountingRefresher());
      await manager.start();
      final guard = guardFor(manager);

      await expectLater(
        guard.run(() async => throw const Fault(HouseSignal.stale)),
        throwsA(isA<Fault<HouseSignal>>()),
      );

      expect(manager.isHeld, isFalse);
      await manager.dispose();
    });

    test('leaves an unauthenticated call alone when it is refused', () async {
      final refresher = CountingRefresher();
      final manager = managerFor(refresher);
      await manager.start();
      final guard = guardFor(manager);

      await expectLater(
        guard.run(
          () async => throw const Fault(HouseSignal.stale),
          authenticated: false,
        ),
        throwsA(isA<Fault<HouseSignal>>()),
      );

      expect(refresher.callCount, 0);
      expect(manager.isHeld, isTrue);
      await manager.dispose();
    });

    test('hands a shared answer to every caller that joined', () async {
      final guard = CallGuard<HouseSignal>(
        duplicateSignal: HouseSignal.duplicate,
      );
      final blocked = Completer<int>();
      var runs = 0;

      final waiting = [
        guard.share(() {
          runs++;
          return blocked.future;
        }, key: 'brand/7'),
        guard.share(() {
          runs++;
          return blocked.future;
        }, key: 'brand/7'),
        guard.share(() {
          runs++;
          return blocked.future;
        }, key: 'brand/7'),
      ];
      await pumpEventQueue();
      blocked.complete(42);

      expect(await Future.wait(waiting), [42, 42, 42]);
      expect(runs, 1);
    });

    test('hands the same failure to every caller that joined', () async {
      final guard = CallGuard<HouseSignal>(
        duplicateSignal: HouseSignal.duplicate,
      );
      final blocked = Completer<int>();
      var runs = 0;

      Future<int> ask() => guard.share(() {
        runs++;
        return blocked.future;
      }, key: 'brand/7');

      final first = expectLater(ask(), throwsA(isA<Fault<HouseSignal>>()));
      final second = expectLater(ask(), throwsA(isA<Fault<HouseSignal>>()));
      await pumpEventQueue();
      blocked.completeError(const Fault(HouseSignal.missing));

      await first;
      await second;
      expect(runs, 1);
    });

    test('releases the key once the shared call has settled', () async {
      final guard = CallGuard<HouseSignal>(
        duplicateSignal: HouseSignal.duplicate,
      );
      var runs = 0;

      Future<int> ask() => guard.share(() async {
        runs++;
        return runs;
      }, key: 'brand/7');

      expect(await ask(), 1);
      expect(guard.isShared('brand/7'), isFalse);
      expect(await ask(), 2);
    });

    test('keeps two different keys apart', () async {
      final guard = CallGuard<HouseSignal>(
        duplicateSignal: HouseSignal.duplicate,
      );
      var runs = 0;

      await Future.wait([
        guard.share(() async {
          runs++;
          return 1;
        }, key: 'brand/7'),
        guard.share(() async {
          runs++;
          return 2;
        }, key: 'brand/8'),
      ]);

      expect(runs, 2);
    });

    test('renews once for a shared call rather than once per caller', () async {
      final refresher = CountingRefresher();
      final manager = managerFor(
        refresher,
        lifetime: const Duration(minutes: 1),
      );
      await manager.start();
      final guard = guardFor(manager);

      await Future.wait([
        guard.share(() async => 'ok', key: 'brand/7'),
        guard.share(() async => 'ok', key: 'brand/7'),
      ]);

      expect(refresher.callCount, 1);
      await manager.dispose();
    });

    test('passes a signal outside the renewal set straight through', () async {
      final refresher = CountingRefresher();
      final manager = managerFor(refresher);
      await manager.start();
      final guard = guardFor(manager);

      await expectLater(
        guard.run(() async => throw const Fault(HouseSignal.missing)),
        throwsA(
          isA<Fault<HouseSignal>>().having(
            (fault) => fault.signal,
            'signal',
            HouseSignal.missing,
          ),
        ),
      );

      expect(refresher.callCount, 0);
      await manager.dispose();
    });
  });
}
