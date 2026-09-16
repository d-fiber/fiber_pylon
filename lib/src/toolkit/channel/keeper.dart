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

import '../observable.dart';
import '../reporter.dart';
import 'backoff.dart';
import 'channel.dart';

/// Holds a [Channel] to the subscriptions it is supposed to have.
///
/// A live connection drops, and when it comes back it knows nothing about what
/// was joined before. Every adapter would otherwise write the same three
/// mechanisms: remember what is wanted, rejoin it after a reopen, and space out
/// attempts so a backend that just fell over is not immediately pushed over
/// again. They are the same mechanisms whatever the backend, so they live here
/// and an adapter writes only [Channel].
///
/// What is wanted is what [join] recorded, not what the connection currently
/// has. That distinction is the whole point: the two disagree during an outage,
/// and this is what makes them agree again.
///
/// The same distinction governs reopening. This reopens because it is supposed
/// to be connected, not because it saw a [ChannelState.closed] go by, so a close
/// this asked for during [reconnect] or [dispose] is not undone a moment later
/// by its own recovery.
class ChannelKeeper<E> {
  final Channel<E> _channel;
  final Backoff _backoff;
  final Reporter _reporter;

  final Set<String> _wanted = <String>{};
  final MutableObservable<ChannelState> _state = MutableObservable(
    ChannelState.closed,
  );

  StreamSubscription<ChannelState>? _stateSubscription;
  Timer? _reopenTimer;
  bool _wantsOpen = false;
  bool _started = false;
  bool _disposed = false;

  /// Keeps [channel] joined to whatever [join] has recorded.
  ///
  /// [backoff] spaces out reopen attempts and is reset as soon as one succeeds.
  ChannelKeeper(
    Channel<E> channel, {
    Backoff? backoff,
    Reporter reporter = const SilentReporter(),
  }) : _channel = channel,
       _backoff = backoff ?? Backoff(),
       _reporter = reporter;

  /// Events from every subscription, as the channel delivers them.
  Stream<E> get events => _channel.events;

  /// Whether the connection is usable.
  Observable<ChannelState> get state => _state;

  /// The subscription names that should be joined.
  Set<String> get wanted => Set<String>.unmodifiable(_wanted);

  /// Opens the connection and starts holding it open.
  ///
  /// Calling this twice does nothing the second time.
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;

    _wantsOpen = true;
    _stateSubscription = _channel.state.listen(_onStateChanged);
    await _open();
  }

  /// Records that [name] should be joined, and joins it when connected.
  ///
  /// Safe before [start] and safe while disconnected: the name is remembered and
  /// joined on the next open.
  Future<void> join(String name) async {
    if (_disposed) return;
    if (!_wanted.add(name)) return;
    if (_state.value != ChannelState.open) return;
    await _guarded(() => _channel.join(name), 'join $name');
  }

  /// Records that [name] should no longer be joined, and leaves it now when
  /// connected.
  Future<void> leave(String name) async {
    if (_disposed) return;
    if (!_wanted.remove(name)) return;
    if (_state.value != ChannelState.open) return;
    await _guarded(() => _channel.leave(name), 'leave $name');
  }

  /// Closes the connection and reopens it, keeping every recorded name.
  ///
  /// What a host calls when something invalidated the connection without
  /// dropping it, a renewed credential being the usual case.
  Future<void> reconnect() async {
    if (_disposed) return;
    _reopenTimer?.cancel();
    _reopenTimer = null;
    _wantsOpen = false;
    await _guarded(_channel.close, 'close');
    if (_disposed) return;
    _wantsOpen = true;
    await _open();
  }

  /// Stops holding the connection and closes it.
  Future<void> dispose() async {
    _disposed = true;
    _wantsOpen = false;
    _reopenTimer?.cancel();
    _reopenTimer = null;
    await _stateSubscription?.cancel();
    _stateSubscription = null;
    await _guarded(_channel.close, 'close');
    await _state.dispose();
  }

  Future<void> _open() async {
    if (_disposed) return;
    await _guarded(_channel.open, 'open');
  }

  void _onStateChanged(ChannelState next) {
    if (_disposed) return;
    _state.value = next;

    switch (next) {
      case ChannelState.open:
        _backoff.reset();
        _reopenTimer?.cancel();
        _reopenTimer = null;
        unawaited(_rejoin());
      case ChannelState.closed:
        _scheduleReopen();
      case ChannelState.opening:
        break;
    }
  }

  Future<void> _rejoin() async {
    for (final name in _wanted.toList()) {
      if (_disposed || _state.value != ChannelState.open) return;
      await _guarded(() => _channel.join(name), 'rejoin $name');
    }
  }

  void _scheduleReopen() {
    if (_disposed || !_started || !_wantsOpen) return;
    if (_reopenTimer != null) return;
    _reopenTimer = Timer(_backoff.next(), () {
      _reopenTimer = null;
      if (_disposed || !_wantsOpen) return;
      if (_state.value == ChannelState.open) return;
      unawaited(_open());
    });
  }

  Future<void> _guarded(Future<void> Function() action, String label) async {
    try {
      await action();
    } catch (error, stackTrace) {
      _reporter.recordError(error, stackTrace, context: {'channel': label});
    }
  }
}
