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

import 'channel.dart';

/// A [Channel] that delivers whatever [publish] hands it, to whoever is
/// listening, with no server on the other end.
///
/// What a test runs against, and what a backend with nothing to connect to
/// uses to demonstrate a live channel without one — the same role
/// `MemoryCredentialStore` plays for a credential.
///
/// [join] and [leave] only record what was asked, in [joined]: nothing here
/// gates delivery on them, because a real [Channel] does not either — the
/// server decides what it sends, and a caller's own `belongsTo` decides what
/// it keeps. What they are for is a test asserting that a name it expected
/// was actually joined.
class MemoryChannel<E> implements Channel<E> {
  final StreamController<E> _events = StreamController<E>.broadcast();
  final StreamController<ChannelState> _state =
      StreamController<ChannelState>.broadcast();
  final Set<String> _joined = <String>{};

  ChannelState _current = ChannelState.closed;
  bool _disposed = false;

  @override
  Stream<E> get events => _events.stream;

  @override
  Stream<ChannelState> get state => _state.stream;

  /// The subscriptions currently joined.
  Set<String> get joined => Set<String>.unmodifiable(_joined);

  /// Whether [open] was called and [close] was not, since.
  bool get isOpen => _current == ChannelState.open;

  @override
  Future<void> open() async {
    if (_disposed || isOpen) return;
    _publish(ChannelState.open);
  }

  @override
  Future<void> close() async {
    _joined.clear();
    _publish(ChannelState.closed);
  }

  @override
  Future<void> join(String name) async => _joined.add(name);

  @override
  Future<void> leave(String name) async => _joined.remove(name);

  /// Delivers [event] to every current listener, as if it had arrived on the
  /// wire.
  void publish(E event) {
    if (!_events.isClosed) _events.add(event);
  }

  /// Closes the channel for good: nothing published after this reaches a
  /// listener.
  Future<void> dispose() async {
    _disposed = true;
    _joined.clear();
    await _events.close();
    await _state.close();
  }

  void _publish(ChannelState next) {
    _current = next;
    if (!_state.isClosed) _state.add(next);
  }
}
