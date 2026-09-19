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

import 'package:fiber_pylon/fiber_pylon.dart';
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
  group('Tenant.follow', () {
    tearDown(Tenant.leave);

    String accountOf(Ticket ticket) => ticket.value;

    test('uses the restored account once the storage has been read', () async {
      final manager = managerFor(ScriptedRefresher([]), stored: ticketLasting(const Duration(hours: 1), value: 'ada'));
      final subscription = Tenant.follow(manager, idOf: accountOf);
      expect(Tenant.current, isNull);

      await manager.start();

      expect(Tenant.current, 'ada');
      await subscription.cancel();
      await manager.dispose();
    });

    test('takes the account of a manager that is already started', () async {
      final manager = managerFor(ScriptedRefresher([]), stored: ticketLasting(const Duration(hours: 1), value: 'ada'));
      await manager.start();

      final subscription = Tenant.follow(manager, idOf: accountOf);

      expect(Tenant.current, 'ada');
      await subscription.cancel();
      await manager.dispose();
    });

    test('touches nothing while the storage has not been read', () async {
      final manager = managerFor(ScriptedRefresher([]));
      Tenant.use('set-by-hand');

      final subscription = Tenant.follow(manager, idOf: accountOf);

      expect(Tenant.current, 'set-by-hand');
      await subscription.cancel();
      await manager.dispose();
    });

    test('switches with a sign-in and leaves with a sign-out', () async {
      final manager = managerFor(ScriptedRefresher([]));
      await manager.start();
      final subscription = Tenant.follow(manager, idOf: accountOf);

      await manager.grant(ticketLasting(const Duration(hours: 1), value: 'ada'));
      expect(Tenant.current, 'ada');

      await manager.grant(ticketLasting(const Duration(hours: 1), value: 'bob'));
      expect(Tenant.current, 'bob');

      await manager.revoke();
      expect(Tenant.current, isNull);

      await subscription.cancel();
      await manager.dispose();
    });

    test('keeps the tenant through a renewal', () async {
      final refresher = ScriptedRefresher([ticketLasting(const Duration(hours: 1), value: 'ada')]);
      final manager = managerFor(refresher, stored: ticketLasting(const Duration(minutes: 2), value: 'ada'));
      await manager.start();
      final subscription = Tenant.follow(manager, idOf: accountOf);
      final seen = <String?>[];
      final watching = Tenant.changes.listen(seen.add);

      await manager.renew();
      await pumpEventQueue();

      expect(refresher.callCount, 1);
      expect(seen, isEmpty);
      expect(Tenant.current, 'ada');
      await watching.cancel();
      await subscription.cancel();
      await manager.dispose();
    });

    test('leaves the tenant when the backend rejects the credential', () async {
      final manager = managerFor(
        ScriptedRefresher([const Fault<HouseSignal>(HouseSignal.rejected)]),
        stored: ticketLasting(const Duration(minutes: 2), value: 'ada'),
      );
      await manager.start();
      final subscription = Tenant.follow(manager, idOf: accountOf);
      expect(Tenant.current, 'ada');

      await manager.renew();

      expect(Tenant.current, isNull);
      await subscription.cancel();
      await manager.dispose();
    });

    test('stops following once cancelled', () async {
      final manager = managerFor(ScriptedRefresher([]));
      await manager.start();
      final subscription = Tenant.follow(manager, idOf: accountOf);
      await subscription.cancel();

      await manager.grant(ticketLasting(const Duration(hours: 1), value: 'ada'));

      expect(Tenant.current, isNull);
      await manager.dispose();
    });
  });
}
