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

enum ReadError { notFound, unknown }

void main() {
  group('HealthMonitor', () {
    test('publishes what the probe answered', () async {
      final monitor = HealthMonitor(name: 'api', probe: () async => false);

      expect(await monitor.check(), isFalse);
      expect(monitor.isHealthy, isFalse);
      await monitor.dispose();
    });

    test('treats a probe that threw as unhealthy', () async {
      final monitor = HealthMonitor(
        name: 'api',
        probe: () async => throw const FormatException('unreachable'),
      );

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
      monitor.healthy.stream.listen(seen.add);

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

  group('Result', () {
    test('folds a success through the ok branch', () {
      const result = OK<int, ReadError>(3);

      expect(result.fold(ok: (data) => data * 2, failure: (_) => 0), 6);
    });

    test('folds a failure through the failure branch', () {
      const result = Failure<int, ReadError>(ReadError.notFound);

      expect(
        result.fold(ok: (data) => 'ok', failure: (error) => error.name),
        'notFound',
      );
    });

    test('map leaves a failure untouched', () {
      const result = Failure<int, ReadError>(ReadError.notFound);

      expect(
        result.map((data) => data * 2),
        const Failure<int, ReadError>(ReadError.notFound),
      );
    });

    test('mapError converts an error into another vocabulary', () {
      const result = Failure<int, ReadError>(ReadError.notFound);

      expect(
        result.mapError((error) => error.name),
        const Failure<int, String>('notFound'),
      );
    });

    test('orElse answers the fallback for a failure', () {
      const result = Failure<int, ReadError>(ReadError.unknown);

      expect(result.orElse(9), 9);
    });

    test('exposes the value and the error where they exist', () {
      const success = OK<int, ReadError>(3);
      const failure = Failure<int, ReadError>(ReadError.unknown);

      expect(success.dataOrNull, 3);
      expect(success.errorOrNull, isNull);
      expect(failure.dataOrNull, isNull);
      expect(failure.errorOrNull, ReadError.unknown);
    });
  });

  group('Singleton', () {
    test('names what was not initialized', () {
      final handle = Singleton<String>('MySdk');

      expect(
        () => handle.instance,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('MySdk.initialize()'),
          ),
        ),
      );
    });

    test('refuses to hold two instances at once', () {
      final handle = Singleton<String>('MySdk')..initialize('first');

      expect(() => handle.initialize('second'), throwsStateError);
    });

    test('accepts another instance once disposed', () {
      final handle = Singleton<String>('MySdk')
        ..initialize('first')
        ..dispose()
        ..initialize('second');

      expect(handle.instance, 'second');
    });
  });

  group('Environments', () {
    test('reports every missing environment variable at once', () {
      const environments = _TestEnvironments(url: '', key: '');

      expect(environments.isComplete, isFalse);
      expect(environments.missing.map((v) => v.name), ['URL', 'KEY']);
    });

    test('accepts an environment that has everything', () {
      const environments = _TestEnvironments(
        url: 'https://example.test',
        key: 'abc',
      );

      expect(environments.isComplete, isTrue);
      expect(environments.missing, isEmpty);
    });
  });
}

final class _TestEnvironments extends Environments {
  final String url;
  final String key;

  const _TestEnvironments({required this.url, required this.key});

  @override
  List<EnvironmentVariable> get variables => [
    EnvironmentVariable(
      name: 'URL',
      value: url,
      reason: 'Where the API lives.',
    ),
    EnvironmentVariable(
      name: 'KEY',
      value: key,
      reason: 'Identifies this app.',
    ),
  ];
}
