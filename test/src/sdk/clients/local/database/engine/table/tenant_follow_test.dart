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
import 'package:fiber_pylon/src/credential/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

enum HouseSignal { rejected }

Credential credentialOf(String holder, {Duration lifetime = const Duration(hours: 1)}) =>
    Credential(token: 'token-$holder', refreshToken: 'again', expiresAt: DateTime.now().add(lifetime), holder: holder);

Future<void> hold([Credential? credential]) async {
  await GetIt.instance.reset();
  GetIt.instance.registerSingleton<Credentials>(
    await Credentials.forTesting(MemoryCredentialStore<Credential>(credential)),
    dispose: (credentials) => credentials.dispose(),
  );
}

void main() {
  tearDown(() async {
    Tenant.leave();
    await GetIt.instance.reset();
  });

  group('Tenant.follow', () {
    test('takes the holder of a credential that was restored before it started', () async {
      await hold(credentialOf('ada'));

      final subscription = Tenant.follow();

      expect(Tenant.current, 'ada');
      await subscription.cancel();
    });

    test('leaves the tenant when no credential is held', () async {
      await hold();
      Tenant.use('stale');

      final subscription = Tenant.follow();

      expect(Tenant.current, isNull);
      await subscription.cancel();
    });

    test('switches with a sign-in and leaves with a sign-out', () async {
      await hold();
      final subscription = Tenant.follow();

      await Credentials.set(credentialOf('ada'));
      expect(Tenant.current, 'ada');

      await Credentials.set(credentialOf('bob'));
      expect(Tenant.current, 'bob');

      await Credentials.clear();
      expect(Tenant.current, isNull);
      await subscription.cancel();
    });

    test('leaves the tenant for a credential that names nobody', () async {
      await hold(credentialOf('ada'));
      final subscription = Tenant.follow();

      await Credentials.set(const Credential(token: 'anonymous'));

      expect(Tenant.current, isNull);
      await subscription.cancel();
    });

    test('keeps the tenant through a renewal', () async {
      await hold(credentialOf('ada', lifetime: const Duration(minutes: 2)));
      var renewals = 0;
      Credentials.renewWith(
        refresh: (current) async {
          renewals++;
          return credentialOf('ada');
        },
        fatalSignals: const {HouseSignal.rejected},
      );
      final subscription = Tenant.follow();
      final seen = <String?>[];
      final watching = Tenant.changes.listen(seen.add);

      await Credentials.renew();
      await pumpEventQueue();

      expect(renewals, 1);
      expect(seen, isEmpty);
      expect(Tenant.current, 'ada');
      await watching.cancel();
      await subscription.cancel();
    });

    test('leaves the tenant when the backend rejects the credential', () async {
      await hold(credentialOf('ada', lifetime: const Duration(minutes: 2)));
      Credentials.renewWith(
        refresh: (current) async => throw const Fault<HouseSignal>(HouseSignal.rejected),
        fatalSignals: const {HouseSignal.rejected},
      );
      final subscription = Tenant.follow();
      expect(Tenant.current, 'ada');

      await Credentials.renew();

      expect(Tenant.current, isNull);
      await subscription.cancel();
    });

    test('stops following once cancelled', () async {
      await hold();
      final subscription = Tenant.follow();
      await subscription.cancel();

      await Credentials.set(credentialOf('ada'));

      expect(Tenant.current, isNull);
    });
  });
}
