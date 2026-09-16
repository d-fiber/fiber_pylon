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

import '../../toolkit/channel/keeper.dart';
import '../segment.dart';

/// One segment of a realtime topic tree, rooted at a live connection.
///
/// The same two growing gestures as [RestNode] carry over here, because
/// composing a topic name is the same problem as composing a path: [node] for
/// text this SDK's author writes, [value] for anything that comes from
/// outside it. [topic] is the only gesture that differs from HTTP, because
/// what it closes the chain into differs: a [RestEndpoint] carries verbs, a
/// [RealtimeTopic] carries a subscription.
final class RealtimeNode<E> {
  RealtimeNode._(this._registry, this._segments, this._name, this._belongsTo);

  final _TopicRegistry<E> _registry;
  final List<String> _segments;
  final String Function(List<String> segments) _name;
  final bool Function(E event, String topic) _belongsTo;

  /// Roots a topic tree over [keeper]'s connection.
  ///
  /// [name] turns composed segments into the topic name this backend expects
  /// on the wire (`segments.join(':')` for a Phoenix channel, `segments.join('/')`
  /// for another convention). [belongsTo] tells which of [keeper]'s events,
  /// all delivered on one shared stream, belong to a given topic name.
  /// Neither has a default: pylon never reads inside `E`, and this keeps the
  /// same discipline rather than guessing a convention that belongs to one
  /// specific server.
  factory RealtimeNode.root({
    required ChannelKeeper<E> keeper,
    required String Function(List<String> segments) name,
    required bool Function(E event, String topic) belongsTo,
  }) => RealtimeNode._(_TopicRegistry(keeper), const [], name, belongsTo);

  /// The branch [literal] below this one. See [RestNode.node].
  RealtimeNode<E> node(String literal) => RealtimeNode._(
    _registry,
    [..._segments, ...literalSegments(literal)],
    _name,
    _belongsTo,
  );

  /// The branch below this one at the opaque segment [value] becomes. See
  /// [RestNode.value].
  RealtimeNode<E> value(Object value) => RealtimeNode._(
    _registry,
    [..._segments, opaqueSegment(value)],
    _name,
    _belongsTo,
  );

  /// The topic at [literal], relative to this branch, ready to be listened
  /// to.
  ///
  /// [literal] follows the same rule as [node]'s argument, and defaults to
  /// empty to name this branch's own topic. Two calls that compose the same
  /// segments from the same root share one [RealtimeTopic], and therefore one
  /// join on the wire.
  RealtimeTopic<E> topic([String literal = '']) {
    final segments = literal.isEmpty
        ? _segments
        : [..._segments, ...literalSegments(literal)];
    return RealtimeTopic._(_registry, _name(segments), _belongsTo);
  }
}

/// One joinable topic, shared across every [RealtimeNode.topic] call that
/// composes the same name from the same root.
///
/// [ChannelKeeper.leave] retires a name from a set with no notion of a second
/// listener still wanting it, so two independent subscribers composing the
/// same topic name would otherwise race: whichever cancels first would
/// silence the other. [events] closes this the way a broadcast
/// `StreamController` already closes it for its own listeners, joined on the
/// first and left on the last, because the registry behind it hands out the
/// same controller to both.
final class RealtimeTopic<E> {
  RealtimeTopic._(this._registry, this._name, this._belongsTo);

  final _TopicRegistry<E> _registry;
  final String _name;
  final bool Function(E event, String topic) _belongsTo;

  /// The name this topic joins, in the wire form the backend expects.
  String get name => _name;

  /// Events on this topic, for as long as something is listening.
  ///
  /// Joins the moment the first listener attaches and leaves once the last
  /// one detaches. There is no separate `join`/`leave` vocabulary to
  /// remember: listening to and cancelling this stream already mean exactly
  /// that.
  Stream<E> get events => _registry.eventsFor(_name, _belongsTo);
}

/// Shares one [ChannelKeeper] subscription across every [RealtimeTopic] built
/// for the same resolved name.
class _TopicRegistry<E> {
  _TopicRegistry(this._keeper);

  final ChannelKeeper<E> _keeper;
  final Map<String, _SharedTopic<E>> _topics = {};

  Stream<E> eventsFor(
    String name,
    bool Function(E event, String topic) belongsTo,
  ) => _topics
      .putIfAbsent(name, () => _SharedTopic(_keeper, name, belongsTo))
      .stream;
}

/// The one controller a resolved topic name shares across every listener.
///
/// `onListen`/`onCancel` of a broadcast `StreamController` already fire only
/// on the zero-to-one and one-to-zero transitions among that controller's own
/// listeners, so this needs no counter of its own: it joins [_keeper] once
/// when the shared controller gains its first listener and leaves once it
/// loses its last, whatever the number of listeners in between.
class _SharedTopic<E> {
  _SharedTopic(this._keeper, this._name, this._belongsTo) {
    _controller = StreamController<E>.broadcast(
      onListen: _onListen,
      onCancel: _onCancel,
    );
  }

  final ChannelKeeper<E> _keeper;
  final String _name;
  final bool Function(E event, String topic) _belongsTo;
  late final StreamController<E> _controller;
  StreamSubscription<E>? _upstream;

  Stream<E> get stream => _controller.stream;

  void _onListen() {
    _upstream = _keeper.events
        .where((event) => _belongsTo(event, _name))
        .listen(_controller.add, onError: _controller.addError);
    unawaited(_keeper.join(_name));
  }

  Future<void> _onCancel() async {
    await _upstream?.cancel();
    _upstream = null;
    await _keeper.leave(_name);
  }
}
