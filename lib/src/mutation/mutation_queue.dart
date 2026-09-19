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

import '../common/backoff.dart';
import '../common/fault.dart';
import '../common/health_monitor.dart';
import '../common/reporter.dart';
import 'mutation.dart';
import 'mutation_store.dart';

/// Replays a [MutationStore]'s queue against the network, one mutation at a
/// time, and the reason a project only has to write [perform] and
/// [resolve].
///
/// This is the write half of offline-first, and it is the same policy
/// whatever the mutation actually does: persist before attempting, replay
/// in the order it was enqueued, never skip a head that failed for a reason
/// that will pass, and never guess what a conflict or a permanent failure
/// means for one particular server — both are asked for, the same
/// discipline `CallGuard.renewOn` and `Credentials.renewWith`'s
/// `fatalSignals` already hold.
///
/// `T` is the project's own mutation type, `S` the adapter's fault signal.
/// [conflictSignals] and [permanentSignals] partition the signals a replay
/// can fail with: everything else is treated as retriable and waited out
/// with [Backoff]. A signal in neither set is retried indefinitely, the
/// same way `ChannelKeeper` reopens a dropped connection indefinitely,
/// because nothing here can tell "still offline" apart from "will never
/// work" without being told which is which.
///
/// ```dart
/// final queue = MutationQueue<UpdateName, AdminSignal>(
///   store: SqfliteMutationStore(),
///   perform: (mutation) => api.renameBrand(mutation.id, mutation.name),
///   resolve: (local, conflict) => local.copyWith(
///     name: (conflict.details as Map)['name'] as String,
///   ),
///   encode: (mutation) => jsonEncode(mutation.toJson()),
///   decode: (raw) => UpdateName.fromJson(jsonDecode(raw)),
///   conflictSignals: {AdminSignal.staleVersion},
///   permanentSignals: {AdminSignal.validationFailed},
///   health: reachability,
/// );
/// ```
class MutationQueue<T, S extends Object> {
  final MutationStore _store;
  final Future<void> Function(T mutation) _perform;
  final T Function(T local, Fault<S> conflict) _resolve;
  final String Function(T mutation) _encode;
  final T Function(String raw) _decode;
  final Set<S> _conflictSignals;
  final Set<S> _permanentSignals;
  final Backoff Function() _newBackoff;
  final HealthMonitor? _health;
  final Reporter _reporter;

  Future<void>? _draining;

  /// Queues mutations durably in [store], replaying each through [perform].
  ///
  /// [perform] carries out one mutation and throws a [Fault] naming what
  /// went wrong, the same contract every pylon operation already holds.
  ///
  /// [resolve] is called when a replay fails with a signal in
  /// [conflictSignals]. It receives the mutation as this device last left
  /// it and the [Fault] the conflict was reported with, and returns the
  /// mutation to replay instead — reading [Fault.details] for whatever the
  /// backend sent about the remote state is entirely this callback's own
  /// business, since no shape is common to two backends.
  ///
  /// [permanentSignals] names the failures worth no further attempt: a
  /// replay that fails with one of these is dropped from the queue and
  /// reported, never retried. Both sets are required and have no default,
  /// the same reason `Credentials.renewWith`'s `fatalSignals` has none: pylon
  /// cannot know which of an adapter's signals means which, and guessing
  /// wrong is expensive in both directions.
  ///
  /// [encode] and [decode] are how [T] survives inside [store], which holds
  /// only opaque text.
  ///
  /// [health], when given, is consulted before a [drain] starts and again
  /// before a retry, so a device known to be offline does not spend a
  /// backoff cycle discovering what it already knows.
  MutationQueue({
    required MutationStore store,
    required Future<void> Function(T mutation) perform,
    required T Function(T local, Fault<S> conflict) resolve,
    required String Function(T mutation) encode,
    required T Function(String raw) decode,
    required Set<S> conflictSignals,
    required Set<S> permanentSignals,
    HealthMonitor? health,
    Backoff Function()? backoff,
    Reporter reporter = const SilentReporter(),
  }) : _store = store,
       _perform = perform,
       _resolve = resolve,
       _encode = encode,
       _decode = decode,
       _conflictSignals = conflictSignals,
       _permanentSignals = permanentSignals,
       _health = health,
       _newBackoff = backoff ?? Backoff.new,
       _reporter = reporter;

  /// Enqueues [mutation] durably, before any network attempt is made.
  Future<void> enqueue(T mutation) async {
    await _store.enqueue(_encode(mutation));
  }

  /// Every mutation still waiting, oldest first, decoded back to [T].
  Future<List<T>> pending() async =>
      (await _store.readAll()).map((m) => _decode(m.payload)).toList();

  /// Replays the queue from its head, stopping as soon as one mutation
  /// cannot be completed yet.
  ///
  /// Does nothing when [health] is given and reports unhealthy. A caller
  /// arriving while a drain is already running waits on that same drain
  /// rather than starting a second one racing the same head.
  Future<void> drain() {
    final running = _draining;
    if (running != null) return running;
    if (_health != null && !_health.isHealthy) return Future<void>.value();

    final started = _drain();
    _draining = started;
    return started.whenComplete(() => _draining = null);
  }

  Future<void> _drain() async {
    while (true) {
      if (_health != null && !_health.isHealthy) return;

      final queued = await _store.readAll();
      if (queued.isEmpty) return;

      final resolved = await _attempt(queued.first);
      if (!resolved) return;
    }
  }

  Future<bool> _attempt(QueuedMutation head) async {
    var payload = head.payload;
    var mutation = _decode(payload);
    final backoff = _newBackoff();

    while (true) {
      try {
        await _perform(mutation);
        await _store.remove(head.idempotencyKey);
        return true;
      } on Fault<S> catch (fault) {
        if (_permanentSignals.contains(fault.signal)) {
          _reporter.log(
            'Mutation ${head.idempotencyKey} dropped, permanent: $fault',
          );
          await _store.remove(head.idempotencyKey);
          return true;
        }

        if (_conflictSignals.contains(fault.signal)) {
          mutation = _resolve(mutation, fault);
          payload = _encode(mutation);
          await _store.update(head.idempotencyKey, payload);
          continue;
        }

        if (_health != null && !_health.isHealthy) return false;
        await Future<void>.delayed(backoff.next());
      }
    }
  }
}
