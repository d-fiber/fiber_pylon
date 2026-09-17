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

import 'observable.dart';
import 'reporter.dart';

/// A yes-or-no condition that is both asked about and reported on.
///
/// Reachability, whether the backend is answering, whether a tunnel is up: each
/// is a flag a screen reads, a probe that can be run on demand or on a timer, and
/// a passive signal from code that just found out the hard way. Writing that
/// three times produces three slightly different versions, so it is written once
/// here.
///
/// What is being monitored is entirely the project's business. This holds a
/// boolean and nothing else.
class HealthMonitor {
  final String _name;
  final Future<bool> Function()? _probe;
  final Duration? _interval;
  final Reporter _reporter;
  final MutableObservable<bool> _healthy;

  Timer? _timer;
  Future<bool>? _inFlight;
  bool _disposed = false;

  /// Monitors the condition called [name], starting out at [initial].
  ///
  /// [probe] answers the question on demand and is what [check] runs. Without
  /// one the monitor only ever changes through [report], which is what a purely
  /// passive signal needs.
  ///
  /// [interval] runs the probe on a timer as well. Leave it `null` to probe only
  /// when asked, which is the cheaper default and usually the right one when
  /// something else already reports failures as they happen.
  HealthMonitor({
    required String name,
    Future<bool> Function()? probe,
    bool initial = true,
    Duration? interval,
    Reporter reporter = const SilentReporter(),
  }) : _name = name,
       _probe = probe,
       _interval = interval,
       _reporter = reporter,
       _healthy = MutableObservable(initial) {
    final period = _interval;
    if (period != null && _probe != null) {
      _timer = Timer.periodic(period, (_) => unawaited(check()));
    }
  }

  /// What is being monitored.
  String get name => _name;

  /// Whether the condition currently holds.
  Observable<bool> get healthy => _healthy;

  /// Whether the condition currently holds, read without a subscription.
  bool get isHealthy => _healthy.value;

  /// Runs the probe and publishes what it answered.
  ///
  /// Concurrent callers share one run. Without a probe this answers the current
  /// value without doing anything.
  ///
  /// A probe that throws counts as unhealthy: an exception means the question
  /// could not be answered, and treating that as healthy is how an outage stays
  /// invisible.
  Future<bool> check() {
    final active = _inFlight;
    if (active != null) return active;

    final probe = _probe;
    if (probe == null || _disposed) return Future<bool>.value(_healthy.value);

    final run = _run(probe);
    _inFlight = run;
    return run;
  }

  /// Publishes [healthy] without running the probe.
  ///
  /// What code that just discovered the answer calls: a call that failed to
  /// reach anything reports `false`, one that came back reports `true`. Nothing
  /// is published when the value has not changed.
  void report({required bool healthy}) {
    if (_disposed) return;
    _healthy.value = healthy;
  }

  /// Stops the timer and closes the observable.
  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    await _healthy.dispose();
  }

  Future<bool> _run(Future<bool> Function() probe) async {
    try {
      final answer = await probe();
      if (!_disposed) _healthy.value = answer;
      return answer;
    } catch (error, stackTrace) {
      _reporter.recordError(error, stackTrace, context: {'probe': _name});
      if (!_disposed) _healthy.value = false;
      return false;
    } finally {
      _inFlight = null;
    }
  }
}
