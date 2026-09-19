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
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HealthMonitor', () {
    test('publishes what the probe answered', () async {
      final monitor = HealthMonitor(name: 'api', probe: () async => false);

      expect(await monitor.check(), isFalse);
      expect(monitor.isHealthy, isFalse);
      await monitor.dispose();
    });

    test('treats a probe that threw as unhealthy', () async {
      final monitor = HealthMonitor(name: 'api', probe: () async => throw const FormatException('unreachable'));

      expect(await monitor.check(), isFalse);
      await monitor.dispose();
    });

    test('shares one run between concurrent checks', () async {
      final blocked = Completer<bool>();
      var runs = 0;
      final monitor = HealthMonitor(
        name: 'api',
        probe: () {
          runs++;
          return blocked.future;
        },
      );

      final waiting = [monitor.check(), monitor.check()];
      await pumpEventQueue();
      blocked.complete(true);
      await Future.wait(waiting);

      expect(runs, 1);
      await monitor.dispose();
    });

    test('accepts a passive report without a probe', () async {
      final monitor = HealthMonitor(name: 'network');

      monitor.report(healthy: false);

      expect(monitor.isHealthy, isFalse);
      await monitor.dispose();
    });

    test('stays quiet when the answer has not changed', () async {
      final monitor = HealthMonitor(name: 'network');
      final seen = <bool>[];
      monitor.healthy.stream.skip(1).listen(seen.add);

      monitor.report(healthy: true);
      monitor.report(healthy: false);
      monitor.report(healthy: false);
      await pumpEventQueue();

      expect(seen, [false]);
      await monitor.dispose();
    });

    test('answers the held value when there is no probe to run', () async {
      final monitor = HealthMonitor(name: 'network', initial: false);

      expect(await monitor.check(), isFalse);
      await monitor.dispose();
    });
  });
}
