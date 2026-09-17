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
import 'dart:math';

import 'package:fiber_pylon/fiber_pylon.dart';
import 'package:flutter_test/flutter_test.dart';

enum SyncSignal { conflict, validationFailed, unreachable }

class RenameMutation {
  final String id;
  final String name;

  const RenameMutation(this.id, this.name);
}

String _encode(RenameMutation mutation) => '${mutation.id}|${mutation.name}';

RenameMutation _decode(String raw) {
  final parts = raw.split('|');
  return RenameMutation(parts[0], parts[1]);
}

class ScriptedPerform {
  final List<Object?> script;
  final List<RenameMutation> received = [];
  int _index = 0;

  ScriptedPerform(this.script);

  int get callCount => received.length;

  Future<void> call(RenameMutation mutation) async {
    received.add(mutation);
    final step = script[_index < script.length ? _index++ : script.length - 1];
    if (step is Fault) throw step;
  }
}

class BlockingPerform {
  final Completer<void> release = Completer<void>();
  int callCount = 0;

  Future<void> call(RenameMutation mutation) {
    callCount++;
    return release.future;
  }
}

class RecordingReporter implements Reporter {
  final List<String> logs = [];

  @override
  void log(String message) => logs.add(message);

  @override
  void recordError(
    Object error,
    StackTrace? stackTrace, {
    bool fatal = false,
    Map<String, Object?> context = const {},
  }) {}

  @override
  void identify(String? identifier) {}
}

Backoff _immediate() => Backoff(
  initial: const Duration(milliseconds: 5),
  ceiling: const Duration(milliseconds: 5),
  jitter: 0,
  random: Random(1),
);

MutationQueue<RenameMutation, SyncSignal> _queueFor(
  Future<void> Function(RenameMutation) perform, {
  MutationStore? store,
  RenameMutation Function(RenameMutation local, Fault<SyncSignal> conflict)?
  resolve,
  HealthMonitor? health,
  Backoff Function()? backoff,
  Reporter reporter = const SilentReporter(),
}) => MutationQueue<RenameMutation, SyncSignal>(
  store: store ?? MemoryMutationStore(),
  perform: perform,
  resolve: resolve ?? (local, conflict) => local,
  encode: _encode,
  decode: _decode,
  conflictSignals: const {SyncSignal.conflict},
  permanentSignals: const {SyncSignal.validationFailed},
  health: health,
  backoff: backoff ?? _immediate,
  reporter: reporter,
);

void main() {
  group('MutationQueue.enqueue', () {
    test('stores the mutation durably before any network attempt', () async {
      final perform = ScriptedPerform([null]);
      final queue = _queueFor(perform.call);

      await queue.enqueue(const RenameMutation('brand/1', 'Acme'));

      expect(perform.callCount, 0);
      final pending = await queue.pending();
      expect(pending, hasLength(1));
      expect(pending.single.id, 'brand/1');
      expect(pending.single.name, 'Acme');
    });
  });

  group('MutationQueue.pending', () {
    test('decodes every mutation still waiting, oldest first', () async {
      final queue = _queueFor(ScriptedPerform([null]).call);

      await queue.enqueue(const RenameMutation('brand/1', 'Acme'));
      await queue.enqueue(const RenameMutation('brand/2', 'Widget'));

      final pending = await queue.pending();
      expect(pending.map((m) => m.id), ['brand/1', 'brand/2']);
    });
  });

  group('MutationQueue.drain', () {
    test('replays a pending mutation and removes it once it succeeds', () async {
      final perform = ScriptedPerform([null]);
      final queue = _queueFor(perform.call);
      await queue.enqueue(const RenameMutation('brand/1', 'Acme'));

      await queue.drain();

      expect(perform.callCount, 1);
      expect(await queue.pending(), isEmpty);
    });

    test('retries a retriable failure with backoff before succeeding', () async {
      final perform = ScriptedPerform([
        const Fault(SyncSignal.unreachable),
        null,
      ]);
      final queue = _queueFor(perform.call);
      await queue.enqueue(const RenameMutation('brand/1', 'Acme'));

      await queue.drain();

      expect(perform.callCount, 2);
      expect(await queue.pending(), isEmpty);
    });

    test(
      'drops a mutation that fails with a permanent signal, without retrying',
      () async {
        final perform = ScriptedPerform([
          const Fault(SyncSignal.validationFailed),
        ]);
        final reporter = RecordingReporter();
        final queue = _queueFor(perform.call, reporter: reporter);
        await queue.enqueue(const RenameMutation('brand/1', 'Acme'));

        await queue.drain();

        expect(perform.callCount, 1);
        expect(await queue.pending(), isEmpty);
        expect(reporter.logs, isNotEmpty);
      },
    );

    test('calls resolve and replays the merged mutation on a conflict signal', () async {
      final perform = ScriptedPerform([
        const Fault(SyncSignal.conflict, details: 'Acme Renamed Remotely'),
        null,
      ]);
      final queue = _queueFor(
        perform.call,
        resolve: (local, conflict) =>
            RenameMutation(local.id, conflict.details as String),
      );
      await queue.enqueue(const RenameMutation('brand/1', 'Acme'));

      await queue.drain();

      expect(perform.received[0].name, 'Acme');
      expect(perform.received[1].name, 'Acme Renamed Remotely');
      expect(await queue.pending(), isEmpty);
    });

    test(
      'leaves the resolved mutation queued under its resolved value, in '
      'case a restart interrupts the replay',
      () async {
        final store = MemoryMutationStore();
        final health = HealthMonitor(name: 'test');
        final perform = ScriptedPerform([
          const Fault(SyncSignal.conflict, details: 'Remote Name'),
          const Fault(SyncSignal.unreachable),
        ]);
        final queue = _queueFor(
          (mutation) async {
            try {
              await perform.call(mutation);
            } finally {
              if (perform.callCount == 2) health.report(healthy: false);
            }
          },
          store: store,
          resolve: (local, conflict) =>
              RenameMutation(local.id, conflict.details as String),
          health: health,
        );
        await queue.enqueue(const RenameMutation('brand/1', 'Acme'));

        await queue.drain();

        final restarted = MutationQueue<RenameMutation, SyncSignal>(
          store: store,
          perform: perform.call,
          resolve: (local, conflict) => local,
          encode: _encode,
          decode: _decode,
          conflictSignals: const {SyncSignal.conflict},
          permanentSignals: const {SyncSignal.validationFailed},
        );
        final pending = await restarted.pending();
        expect(pending, hasLength(1));
        expect(pending.single.name, 'Remote Name');
      },
    );

    test('does nothing when health reports unhealthy', () async {
      final perform = ScriptedPerform([null]);
      final queue = _queueFor(
        perform.call,
        health: HealthMonitor(name: 'test', initial: false),
      );
      await queue.enqueue(const RenameMutation('brand/1', 'Acme'));

      await queue.drain();

      expect(perform.callCount, 0);
      expect(await queue.pending(), hasLength(1));
    });

    test(
      'stops retrying once health turns unhealthy mid-drain, leaving the '
      'mutation queued',
      () async {
        final health = HealthMonitor(name: 'test');
        final perform = ScriptedPerform([
          const Fault(SyncSignal.unreachable),
          null,
        ]);
        final queue = _queueFor(
          (mutation) async {
            try {
              await perform.call(mutation);
            } finally {
              health.report(healthy: false);
            }
          },
          health: health,
        );
        await queue.enqueue(const RenameMutation('brand/1', 'Acme'));

        await queue.drain();

        expect(perform.callCount, 1);
        expect(await queue.pending(), hasLength(1));
      },
    );

    test('shares one running drain with a caller that arrives while it is in flight', () async {
      final perform = BlockingPerform();
      final queue = _queueFor(perform.call);
      await queue.enqueue(const RenameMutation('brand/1', 'Acme'));

      final first = queue.drain();
      final second = queue.drain();
      perform.release.complete();
      await first;
      await second;

      expect(perform.callCount, 1);
    });
  });
}
