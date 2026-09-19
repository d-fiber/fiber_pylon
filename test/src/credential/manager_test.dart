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
import 'package:fiber_pylon/src/credential/manager.dart';
import 'package:fiber_pylon/src/credential/refresher.dart';
import 'package:fiber_pylon/src/credential/store.dart';
import 'package:flutter_test/flutter_test.dart';

class Ticket {
  final String value;
  final DateTime expiresAt;

  const Ticket(this.value, this.expiresAt);
}

Ticket ticketLasting(Duration lifetime, {String value = 'first'}) => Ticket(value, DateTime.now().add(lifetime));

enum HouseSignal { rejected, unreachable }

class ScriptedRefresher implements CredentialRefresher<Ticket> {
  final List<Object> script;
  final List<Ticket> received = [];
  int _index = 0;

  ScriptedRefresher(this.script);

  int get callCount => received.length;

  @override
  Future<Ticket> refresh(Ticket current) async {
    received.add(current);
    final step = script[_index < script.length ? _index++ : script.length - 1];
    if (step is Fault) throw step;
    return step as Ticket;
  }
}

class BlockingRefresher implements CredentialRefresher<Ticket> {
  final Completer<Ticket> release = Completer<Ticket>();
  int callCount = 0;

  @override
  Future<Ticket> refresh(Ticket current) {
    callCount++;
    return release.future;
  }
}

CredentialManager<Ticket, HouseSignal> managerFor(
  CredentialRefresher<Ticket> refresher, {
  Ticket? stored,
  Duration buffer = const Duration(minutes: 10),
  Duration retryDelay = const Duration(milliseconds: 50),
}) => CredentialManager<Ticket, HouseSignal>(
  store: MemoryCredentialStore<Ticket>(stored),
  refresher: refresher,
  expiresAt: (ticket) => ticket.expiresAt,
  fatalSignals: const {HouseSignal.rejected},
  buffer: buffer,
  retryDelay: retryDelay,
);

void main() {
  group('CredentialManager', () {
    test('publishes nothing held even when storage held nothing', () async {
      final manager = managerFor(ScriptedRefresher([]));
      final seen = <Ticket?>[];
      manager.stream.listen(seen.add);

      await manager.start();
      await pumpEventQueue();

      expect(seen, [null, null]);
      expect(manager.held.value, isFalse);
      expect(manager.isHeld, isFalse);
      await manager.dispose();
    });

    test('restores a stored credential and holds it', () async {
      final stored = ticketLasting(const Duration(hours: 1));
      final manager = managerFor(ScriptedRefresher([]), stored: stored);

      await manager.start();

      expect(manager.value, same(stored));
      expect(manager.isHeld, isTrue);
      await manager.dispose();
    });

    test('leaves a credential alone while it is far from expiry', () async {
      final refresher = ScriptedRefresher([]);
      final manager = managerFor(refresher, stored: ticketLasting(const Duration(hours: 1)));
      await manager.start();

      await manager.ensureFresh();

      expect(refresher.callCount, 0);
      await manager.dispose();
    });

    test('renews a credential that entered the buffer window', () async {
      final renewed = ticketLasting(const Duration(hours: 1), value: 'second');
      final refresher = ScriptedRefresher([renewed]);
      final manager = managerFor(refresher, stored: ticketLasting(const Duration(minutes: 2)));
      await manager.start();

      await manager.ensureFresh();

      expect(refresher.callCount, 1);
      expect(manager.value, same(renewed));
      await manager.dispose();
    });

    test('collapses concurrent renewals into a single exchange', () async {
      final refresher = BlockingRefresher();
      final manager = managerFor(refresher, stored: ticketLasting(const Duration(minutes: 2)));
      await manager.start();

      final waiting = [manager.ensureFresh(), manager.ensureFresh(), manager.renew()];
      await pumpEventQueue();
      refresher.release.complete(ticketLasting(const Duration(hours: 1), value: 'second'));
      await Future.wait(waiting);

      expect(refresher.callCount, 1);
      await manager.dispose();
    });

    test('revokes when the backend refuses the credential', () async {
      final refresher = ScriptedRefresher([const Fault(HouseSignal.rejected)]);
      final manager = managerFor(refresher, stored: ticketLasting(const Duration(minutes: 2)));
      final seen = <Ticket?>[];
      await manager.start();
      manager.stream.listen(seen.add);

      await manager.renew();

      expect(manager.isHeld, isFalse);
      expect(seen.last, isNull);
      await manager.dispose();
    });

    test('keeps the credential when renewal fails for a transient reason', () async {
      final stored = ticketLasting(const Duration(minutes: 2));
      final refresher = ScriptedRefresher([const Fault(HouseSignal.unreachable)]);
      final manager = managerFor(refresher, stored: stored);
      await manager.start();

      await manager.renew();

      expect(manager.isHeld, isTrue);
      expect(manager.value, same(stored));
      await manager.dispose();
    });

    test('retries a deferred renewal as soon as connectivity is restored', () async {
      final renewed = ticketLasting(const Duration(hours: 1), value: 'second');
      final refresher = ScriptedRefresher([const Fault(HouseSignal.unreachable), renewed]);
      final manager = managerFor(
        refresher,
        stored: ticketLasting(const Duration(minutes: 2)),
        retryDelay: const Duration(seconds: 30),
      );
      await manager.start();
      await manager.renew();

      manager.onConnectivityRestored();
      await pumpEventQueue();

      expect(refresher.callCount, 2);
      expect(manager.value, same(renewed));
      await manager.dispose();
    });

    test('schedules with rearm the renewal that start could not', () async {
      var pluggedIn = false;
      final renewed = ticketLasting(const Duration(hours: 1), value: 'second');
      final refresher = ScriptedRefresher([renewed]);
      final manager = CredentialManager<Ticket, HouseSignal>(
        store: MemoryCredentialStore<Ticket>(ticketLasting(const Duration(milliseconds: 120))),
        refresher: refresher,
        expiresAt: (ticket) => ticket.expiresAt,
        fatalSignals: const {HouseSignal.rejected},
        isRenewable: (ticket) => pluggedIn,
        buffer: const Duration(milliseconds: 100),
      );
      await manager.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(refresher.callCount, 0);

      pluggedIn = true;
      manager.rearm();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(refresher.callCount, 1);
      expect(manager.value, same(renewed));
      await manager.dispose();
    });

    test('schedules no timer for a credential too far from expiry, and one for a nearer', () async {
      final durations = <Duration>[];
      final spec = ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          durations.add(duration);
          return parent.createTimer(zone, duration, callback);
        },
      );

      Future<void> startWith(Duration lifetime) => runZoned(() async {
        final manager = managerFor(ScriptedRefresher([]), stored: ticketLasting(lifetime));
        await manager.start();
        await manager.dispose();
      }, zoneSpecification: spec);

      await startWith(const Duration(days: 30));
      expect(durations, isEmpty);

      await startWith(const Duration(hours: 2));
      expect(durations.single, lessThan(const Duration(hours: 2)));
    });

    test('never renews a credential it was told is not renewable', () async {
      final refresher = ScriptedRefresher([]);
      final manager = CredentialManager<Ticket, HouseSignal>(
        store: MemoryCredentialStore<Ticket>(ticketLasting(const Duration(minutes: 2))),
        refresher: refresher,
        expiresAt: (ticket) => ticket.expiresAt,
        fatalSignals: const {HouseSignal.rejected},
        isRenewable: (ticket) => false,
      );
      await manager.start();

      await manager.renew();

      expect(refresher.callCount, 0);
      await manager.dispose();
    });

    test('renews on its own once the scheduled moment arrives', () async {
      final renewed = ticketLasting(const Duration(hours: 1), value: 'second');
      final refresher = ScriptedRefresher([renewed]);
      final manager = managerFor(
        refresher,
        stored: ticketLasting(const Duration(milliseconds: 120)),
        buffer: const Duration(milliseconds: 100),
      );

      await manager.start();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(refresher.callCount, 1);
      expect(manager.value, same(renewed));
      await manager.dispose();
    });

    test('reports staleness only while a credential is held', () async {
      final manager = managerFor(ScriptedRefresher([]));
      await manager.start();

      expect(manager.isStale, isFalse);

      await manager.grant(ticketLasting(const Duration(minutes: 2)));
      expect(manager.isStale, isTrue);
      await manager.dispose();
    });
  });

  group('CredentialManager as an Observable', () {
    test('reads the credential with value and with a call', () async {
      final stored = ticketLasting(const Duration(hours: 1));
      final manager = managerFor(ScriptedRefresher([]), stored: stored);
      expect(manager.value, isNull);

      await manager.start();

      expect(manager.value, same(stored));
      expect(manager(), same(stored));
      await manager.dispose();
    });

    test('gives a new listener the credential in force, then each one that replaces it', () async {
      final stored = ticketLasting(const Duration(minutes: 2), value: 'first');
      final renewed = ticketLasting(const Duration(hours: 1), value: 'second');
      final manager = managerFor(ScriptedRefresher([renewed]), stored: stored);
      await manager.start();
      final seen = <Ticket?>[];
      manager.stream.listen(seen.add);

      await manager.renew();
      await manager.revoke();
      await pumpEventQueue();

      expect(seen, [same(stored), same(renewed), isNull]);
      await manager.dispose();
    });
  });

  group('CredentialManager held', () {
    test('is not held while nothing has been restored or granted', () async {
      final manager = managerFor(ScriptedRefresher([]));

      expect(manager.held.value, isFalse);

      await manager.start();

      expect(manager.held.value, isFalse);
      await manager.dispose();
    });

    test('is held once a stored credential is restored', () async {
      final manager = managerFor(ScriptedRefresher([]), stored: ticketLasting(const Duration(hours: 1)));

      await manager.start();

      expect(manager.held.value, isTrue);
      await manager.dispose();
    });

    test('follows a sign-in and a sign-out', () async {
      final manager = managerFor(ScriptedRefresher([]));
      final seen = <bool>[];
      manager.held.stream.listen(seen.add);
      await manager.start();

      await manager.grant(ticketLasting(const Duration(hours: 1)));
      await manager.revoke();
      await pumpEventQueue();

      expect(seen, [false, true, false]);
      await manager.dispose();
    });

    test('does not wake a listener when the credential is renewed', () async {
      final refresher = ScriptedRefresher([ticketLasting(const Duration(hours: 1), value: 'second')]);
      final manager = managerFor(refresher, stored: ticketLasting(const Duration(minutes: 2)));
      await manager.start();
      final seen = <bool>[];
      manager.held.stream.skip(1).listen(seen.add);

      await manager.renew();
      await pumpEventQueue();

      expect(refresher.callCount, 1);
      expect(seen, isEmpty);
      await manager.dispose();
    });

    test('is dropped when the backend rejects the credential', () async {
      final manager = managerFor(
        ScriptedRefresher([const Fault<HouseSignal>(HouseSignal.rejected)]),
        stored: ticketLasting(const Duration(minutes: 2)),
      );
      await manager.start();

      await manager.renew();

      expect(manager.held.value, isFalse);
      await manager.dispose();
    });

    test('stays held when the backend is only unreachable', () async {
      final manager = managerFor(
        ScriptedRefresher([const Fault<HouseSignal>(HouseSignal.unreachable)]),
        stored: ticketLasting(const Duration(minutes: 2)),
        retryDelay: const Duration(seconds: 30),
      );
      await manager.start();

      await manager.renew();

      expect(manager.held.value, isTrue);
      await manager.dispose();
    });
  });
}
