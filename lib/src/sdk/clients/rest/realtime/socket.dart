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

import 'package:equatable/equatable.dart';

import '../../../../common/reporter.dart';
import 'channel.dart';

/// A duplex link carrying text frames.
///
/// The three things a framed protocol needs from a socket, and nothing else, so
/// that pylon depends on no socket library and a test can drive a channel
/// without a server.
abstract interface class SocketLink {
  /// Frames as they arrive.
  ///
  /// Closing this stream, or letting an error reach it, is how the link reports
  /// that it is gone.
  Stream<String> get inbound;

  /// Sends [frame].
  ///
  /// Throws when the link is already gone, which the channel treats as the link
  /// being gone.
  void send(String frame);

  /// Closes the link.
  Future<void> close();
}

/// Opens a link to [endpoint].
///
/// Supplied by the project, because a socket library is a dependency pylon has
/// no business choosing. `package:fiber_pylon/fiber_pylon_io.dart` carries one built on
/// `dart:io` for a project that has no opinion.
typedef SocketOpener = Future<SocketLink> Function(Uri endpoint);

/// What one incoming frame turned out to be.
///
/// Four cases because four are what the channel has to tell apart. Anything a
/// protocol cannot place is [SocketIgnored], and the channel still counts it as
/// proof that the link is alive.
sealed class SocketFrame<E> {
  const SocketFrame();
}

/// A frame carrying something the caller subscribed for.
final class SocketEvent<E> extends SocketFrame<E> with Equatable {
  /// What arrived, in the project's own event type.
  final E event;

  /// Reports that [event] arrived.
  const SocketEvent(this.event);

  @override
  List<Object?> get props => [event];
}

/// A frame confirming that a subscription is in force.
final class SocketJoined<E> extends SocketFrame<E> with Equatable {
  /// The subscription the server confirmed.
  final String name;

  /// Reports that [name] is joined.
  const SocketJoined(this.name);

  @override
  List<Object?> get props => [name];
}

/// A frame refusing a subscription.
///
/// Telling this apart from a confirmation is the difference between knowing a
/// subscription failed and believing it worked while nothing ever arrives.
final class SocketRejected<E> extends SocketFrame<E> with Equatable {
  /// The subscription the server refused.
  final String name;

  /// Whatever the server said about why, for the report.
  final Object? reason;

  /// Reports that [name] was refused.
  const SocketRejected(this.name, [this.reason]);

  @override
  List<Object?> get props => [name, reason];
}

/// A frame the channel has nothing to do with.
///
/// Heartbeat replies, presence, protocol chatter. It still counts as traffic.
final class SocketIgnored<E> extends SocketFrame<E> with Equatable {
  /// Reports a frame of no interest.
  const SocketIgnored();

  @override
  List<Object?> get props => const [];
}

/// What the frames of one server look like.
///
/// The channel owns when to send and what to do with what comes back; this owns
/// what the bytes are. Swapping a
/// Phoenix server for another kind means writing this, and nothing else.
///
/// References are handed out by the channel and are unique for the life of a
/// link. A protocol that has no use for them ignores them.
abstract interface class SocketProtocol<E> {
  /// Where to connect.
  ///
  /// Asynchronous because it usually carries a credential, which may have to be
  /// renewed first. Called again on every reconnection, so a token that changed
  /// in the meantime is picked up.
  Future<Uri> endpoint();

  /// The frame that subscribes to [name].
  String encodeJoin(String name, int reference);

  /// The frame that unsubscribes from [name].
  ///
  /// [joinReference] is the reference the join used, which a protocol like
  /// Phoenix needs in order to address the right subscription, and [reference]
  /// is a fresh one for this frame.
  String encodeLeave(
    String name, {
    required int joinReference,
    required int reference,
  });

  /// The frame that asks the server to prove it is there.
  String encodeHeartbeat(int reference);

  /// What [raw] amounts to.
  ///
  /// [references] maps every reference the channel has handed out on this link
  /// to the subscription it was for, so a reply that answers by reference can be
  /// resolved to a name without the protocol keeping its own books.
  ///
  /// Must not throw. A frame that makes no sense is [SocketIgnored], and a
  /// protocol that throws instead turns one malformed frame into a dead link.
  SocketFrame<E> decode(String raw, Map<int, String> references);
}

/// A [Channel] over a framed socket.
///
/// This is the policy half of realtime, and it exists because the three things
/// that go wrong with a socket go wrong the same way whatever the server is.
///
/// **A link that died without saying so.** A connection that drops silently, and
/// they very often do when a network changes underneath, leaves a socket that
/// reports nothing: no close, no error, no frames. Waiting for a close that will
/// never come is how an app sits there looking connected and receiving nothing.
/// This sends a heartbeat every [heartbeatInterval] and gives up on the link if
/// nothing at all arrives for [silence], because traffic is the only evidence a
/// link is alive.
///
/// **A subscription that was refused.** A server that turns down a join usually
/// says so in a frame nobody reads, and the result looks exactly like a quiet
/// topic. Here a refusal is reported and the name is not recorded as joined.
///
/// **Two connections at once.** Opening while an open is already under way is
/// easy to do from a reconnect timer and a credential change arriving together.
/// It leaves an orphaned socket whose frames still arrive. Opening is
/// single-flight here.
///
/// What this does not do is decide when to reconnect or what to rejoin: that is
/// [ChannelKeeper], which already holds it for every kind of channel.
class SocketChannel<E> implements Channel<E> {
  final SocketProtocol<E> _protocol;
  final SocketOpener _opener;
  final Duration _heartbeatInterval;
  final Duration _silence;
  final Reporter _reporter;

  final StreamController<E> _events = StreamController<E>.broadcast();
  final StreamController<ChannelState> _state =
      StreamController<ChannelState>.broadcast();

  final Map<int, String> _references = <int, String>{};
  final Map<String, int> _joinReferences = <String, int>{};
  final Set<String> _confirmed = <String>{};

  SocketLink? _link;
  StreamSubscription<String>? _inbound;
  Timer? _heartbeat;
  Timer? _silenceTimer;
  Future<void>? _opening;
  int _reference = 0;
  bool _disposed = false;

  /// Speaks [protocol] over a link obtained from [opener].
  ///
  /// [heartbeatInterval] is how often to prod the server. [silence] is how long
  /// the channel tolerates hearing nothing at all before treating the link as
  /// gone, and it must be longer than [heartbeatInterval] or every quiet moment
  /// looks like a failure.
  SocketChannel({
    required SocketProtocol<E> protocol,
    required SocketOpener opener,
    Duration heartbeatInterval = const Duration(seconds: 30),
    Duration silence = const Duration(seconds: 75),
    Reporter reporter = const SilentReporter(),
  }) : assert(
         silence > heartbeatInterval,
         'silence must outlast heartbeatInterval, or a quiet link looks dead',
       ),
       _protocol = protocol,
       _opener = opener,
       _heartbeatInterval = heartbeatInterval,
       _silence = silence,
       _reporter = reporter;

  @override
  Stream<E> get events => _events.stream;

  @override
  Stream<ChannelState> get state => _state.stream;

  /// The subscriptions the server has confirmed.
  ///
  /// A name that was asked for but not yet answered is absent, which is what
  /// separates asking from being subscribed.
  Set<String> get confirmed => Set<String>.unmodifiable(_confirmed);

  @override
  Future<void> open() {
    final opening = _opening;
    if (opening != null) return opening;
    if (_link != null || _disposed) return Future<void>.value();

    final started = _open();
    _opening = started;
    return started.whenComplete(() => _opening = null);
  }

  @override
  Future<void> close() async {
    await _teardown(publishClosed: true);
  }

  @override
  Future<void> join(String name) async {
    final reference = _nextReference(name);
    _joinReferences[name] = reference;
    _sendOrFail(_protocol.encodeJoin(name, reference), 'join $name');
  }

  @override
  Future<void> leave(String name) async {
    final joinReference = _joinReferences.remove(name);
    _confirmed.remove(name);
    if (joinReference == null) return;

    _sendOrFail(
      _protocol.encodeLeave(
        name,
        joinReference: joinReference,
        reference: _nextReference(name),
      ),
      'leave $name',
    );
  }

  /// Sends [frame] as it is.
  ///
  /// The way out for what a protocol needs to say that this does not model, a
  /// renewed credential pushed to an open link being the usual one. Reconnecting
  /// would also work and is what happens if this is not used, at the cost of
  /// every subscription being joined again.
  void push(String frame) => _sendOrFail(frame, 'push');

  /// Closes the link and stops everything.
  Future<void> dispose() async {
    _disposed = true;
    await _teardown(publishClosed: false);
    await _events.close();
    await _state.close();
  }

  Future<void> _open() async {
    _publish(ChannelState.opening);

    try {
      final endpoint = await _protocol.endpoint();
      if (_disposed) return;

      final link = await _opener(endpoint);
      if (_disposed) {
        await link.close();
        return;
      }

      _link = link;
      _inbound = link.inbound.listen(
        _onFrame,
        onDone: _onLinkGone,
        onError: (Object error, StackTrace stackTrace) {
          _reporter.recordError(
            error,
            stackTrace,
            context: {'socket': 'inbound'},
          );
          _onLinkGone();
        },
      );

      _publish(ChannelState.open);
      _restartHeartbeat();
      _restartSilence();
    } catch (error, stackTrace) {
      _reporter.recordError(error, stackTrace, context: {'socket': 'open'});
      await _teardown(publishClosed: true);
    }
  }

  void _onFrame(String raw) {
    _restartSilence();

    final SocketFrame<E> frame;
    try {
      frame = _protocol.decode(raw, Map<int, String>.unmodifiable(_references));
    } catch (error, stackTrace) {
      _reporter.recordError(error, stackTrace, context: {'socket': 'decode'});
      return;
    }

    switch (frame) {
      case SocketEvent<E>(:final event):
        if (!_events.isClosed) _events.add(event);
      case SocketJoined<E>(:final name):
        _confirmed.add(name);
      case SocketRejected<E>(:final name, :final reason):
        _confirmed.remove(name);
        _joinReferences.remove(name);
        _reporter.log('Subscription refused: $name ($reason)');
      case SocketIgnored<E>():
        break;
    }
  }

  void _onLinkGone() {
    if (_disposed) return;
    unawaited(_teardown(publishClosed: true));
  }

  void _restartHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(_heartbeatInterval, (_) {
      _sendOrFail(_protocol.encodeHeartbeat(_nextReference(null)), 'heartbeat');
    });
  }

  void _restartSilence() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(_silence, () {
      _reporter.log('Socket silent for ${_silence.inSeconds}s, dropping it');
      _onLinkGone();
    });
  }

  int _nextReference(String? name) {
    final reference = ++_reference;
    if (name != null) _references[reference] = name;
    return reference;
  }

  void _sendOrFail(String frame, String label) {
    final link = _link;
    if (link == null) {
      throw StateError('Cannot $label: the socket is not open');
    }

    try {
      link.send(frame);
    } catch (error, stackTrace) {
      _reporter.recordError(error, stackTrace, context: {'socket': label});
      _onLinkGone();
      rethrow;
    }
  }

  Future<void> _teardown({required bool publishClosed}) async {
    _heartbeat?.cancel();
    _heartbeat = null;
    _silenceTimer?.cancel();
    _silenceTimer = null;

    await _inbound?.cancel();
    _inbound = null;

    final link = _link;
    _link = null;
    _references.clear();
    _joinReferences.clear();
    _confirmed.clear();

    if (link != null) {
      try {
        await link.close();
      } catch (error, stackTrace) {
        _reporter.recordError(error, stackTrace, context: {'socket': 'close'});
      }
    }

    if (publishClosed) _publish(ChannelState.closed);
  }

  void _publish(ChannelState next) {
    if (!_state.isClosed) _state.add(next);
  }
}
