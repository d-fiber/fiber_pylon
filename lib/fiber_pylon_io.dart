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

/// The pieces of pylon that need `dart:io`.
///
/// Kept out of `package:fiber_pylon/fiber_pylon.dart` so that importing pylon does not stop
/// a project from compiling for the web. A project that runs on a desktop or a
/// device imports this as well; one that also targets the web supplies its own
/// [SocketLink] over a socket library that works there.
library;

import 'dart:async';
import 'dart:io';

import 'fiber_pylon.dart';

/// A [SocketLink] over the WebSocket of `dart:io`.
///
/// Text frames only, which is what a framed protocol uses. A binary frame that
/// arrives is dropped rather than crashing the link.
class WebSocketLink implements SocketLink {
  final WebSocket _socket;
  final StreamController<String> _inbound =
      StreamController<String>.broadcast();
  StreamSubscription<dynamic>? _subscription;

  WebSocketLink._(this._socket) {
    _subscription = _socket.listen(
      (Object? frame) {
        if (frame is String && !_inbound.isClosed) _inbound.add(frame);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_inbound.isClosed) _inbound.addError(error, stackTrace);
      },
      onDone: () {
        if (!_inbound.isClosed) _inbound.close();
      },
    );
  }

  /// Connects to [endpoint].
  ///
  /// [headers] are sent with the upgrade request, for a server that
  /// authenticates there rather than in the query string.
  static Future<SocketLink> connect(
    Uri endpoint, {
    Map<String, Object>? headers,
  }) async => WebSocketLink._(
    await WebSocket.connect(endpoint.toString(), headers: headers),
  );

  /// A [SocketOpener] that connects with [headers] on every attempt.
  static SocketOpener opener({Map<String, Object>? headers}) =>
      (endpoint) => connect(endpoint, headers: headers);

  @override
  Stream<String> get inbound => _inbound.stream;

  @override
  void send(String frame) => _socket.add(frame);

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    if (!_inbound.isClosed) await _inbound.close();
    await _socket.close();
  }
}
