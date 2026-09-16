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

import 'dart:math';

/// How long to wait before trying again, growing with each failure.
///
/// Jitter is on by default and matters more than the growth: without it every
/// client that lost the same connection comes back at the same instant, and the
/// thing that just recovered falls over again.
class Backoff {
  final Duration _initial;
  final Duration _ceiling;
  final double _factor;
  final double _jitter;
  final Random _random;

  int _attempts = 0;

  /// Waits [initial] the first time, multiplying by [factor] afterwards without
  /// ever exceeding [ceiling].
  ///
  /// [jitter] is the fraction of the delay that is randomised, between `0` and
  /// `1`: at `0.2` a five second delay lands anywhere between four and six.
  /// [random] is there so a test can make the sequence predictable.
  Backoff({
    Duration initial = const Duration(seconds: 1),
    Duration ceiling = const Duration(seconds: 30),
    double factor = 2.0,
    double jitter = 0.2,
    Random? random,
  }) : _initial = initial,
       _ceiling = ceiling,
       _factor = factor,
       _jitter = jitter,
       _random = random ?? Random();

  /// How many delays have been handed out since the last [reset].
  int get attempts => _attempts;

  /// The next delay, and one more attempt counted.
  Duration next() {
    final grown = _initial.inMicroseconds * pow(_factor, _attempts);
    final capped = min(grown, _ceiling.inMicroseconds.toDouble());
    _attempts++;

    if (_jitter <= 0) return Duration(microseconds: capped.round());

    final spread = capped * _jitter;
    final shifted = capped - spread + _random.nextDouble() * spread * 2;
    return Duration(microseconds: max(0, shifted.round()));
  }

  /// Forgets every attempt, so the next delay is [initial] again.
  ///
  /// Called on success. Forgetting to is what leaves a healthy connection
  /// waiting half a minute after a hiccup it already recovered from.
  void reset() {
    _attempts = 0;
  }
}
