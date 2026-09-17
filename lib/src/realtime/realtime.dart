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

import '../common/segment.dart';
import 'keeper.dart';

/// One segment of a realtime topic tree, rooted at a live connection.
///
/// [path] never talks to the connection, it only remembers one more branch.
/// Any node can become a subscribable [RealtimeTopic] directly through
/// [topic], because a node built by [path] is always a complete address —
/// there is no partly-composed state left to protect against, as long as
/// every parameter it carries has been resolved by [parameters] first.
final class RealtimeNode<E> {
  RealtimeNode._(this._registry, this._segments, this._name, this._belongsTo);

  final _TopicRegistry<E> _registry;
  final List<_PathPart> _segments;
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

  /// The resolved segments this node addresses.
  ///
  /// Throws a [StateError] while a parameter [path] left unresolved remains,
  /// since that is not an address yet, only the shape of one.
  List<String> get _resolvedSegments {
    final unresolved = _segments.whereType<_Parameter>();
    if (unresolved.isNotEmpty) {
      throw StateError(
        'unresolved ${unresolved.map((p) => p.name).join(', ')}: call '
        'parameters() first',
      );
    }
    return _segments.cast<_Literal>().map((s) => s.value).toList();
  }

  /// The branch [build] describes below this one.
  ///
  /// [build] receives an empty [RealtimePath] and returns the one it
  /// composed, through [RealtimePath.segment] for text this SDK's own author
  /// writes once, such as `'brand'`, and [RealtimePath.parameter] for a value
  /// [parameters] resolves later, at the point a caller actually has it:
  ///
  /// ```dart
  /// final brand = topics.path((p) => p.segment('brand').parameter('id'));
  /// ```
  ///
  /// [RealtimePath.parameter] is the only place an identifier or any value
  /// that did not originate in this SDK's own source belongs — never
  /// interpolated into a [RealtimePath.segment] directly, which would let it
  /// inject extra segments unnoticed.
  RealtimeNode<E> path(RealtimePath Function(RealtimePath) build) =>
      RealtimeNode._(
        _registry,
        [..._segments, ...build(const RealtimePath._([]))._parts],
        _name,
        _belongsTo,
      );

  /// Resolves every parameter [path] left behind, replacing each with the
  /// single, opaque, percent-encoded segment [build] supplied for it.
  ///
  /// [build] receives an empty [RealtimeParameters] and returns the one it
  /// composed, through [RealtimeParameters.parameter] once per placeholder.
  ///
  /// Throws an [ArgumentError] naming what is missing when a parameter has
  /// nothing supplied for it, and one naming what is unused when [build]
  /// supplies a name no parameter asked for — a call is only ready once the
  /// two match exactly.
  RealtimeNode<E> parameters(
    RealtimeParameters Function(RealtimeParameters) build,
  ) {
    final values = build(const RealtimeParameters._({}))._values;
    final used = <String>{};
    final resolved = _segments.map((part) {
      if (part is! _Parameter) return part;
      final value = values[part.name];
      if (value == null) {
        throw ArgumentError('missing a value for parameter "${part.name}"');
      }
      used.add(part.name);
      return _Literal(opaqueSegment(value));
    }).toList();

    final unused = values.keys.toSet().difference(used);
    if (unused.isNotEmpty) {
      throw ArgumentError(
        'parameters for $unused were given but nothing needs them',
      );
    }
    return RealtimeNode._(_registry, resolved, _name, _belongsTo);
  }

  /// The topic this node addresses, ready to be listened to.
  ///
  /// Two calls that compose the same segments from the same root share one
  /// [RealtimeTopic], and therefore one join on the wire.
  RealtimeTopic<E> topic() =>
      RealtimeTopic._(_registry, _name(_resolvedSegments), _belongsTo);
}

/// One branch of segments composed inside [RealtimeNode.path].
final class RealtimePath {
  const RealtimePath._(this._parts);

  final List<_PathPart> _parts;

  /// Appends [literal] to this branch.
  ///
  /// [literal] is text this SDK's own author writes once while wiring a
  /// backend, such as `'brand'`. It may carry several segments separated by
  /// `/`, because nothing external ever reaches this parameter.
  RealtimePath segment(String literal) => RealtimePath._([
    ..._parts,
    ...literalSegments(literal).map(_Literal.new),
  ]);

  /// Appends a parameter named [name], resolved later by
  /// [RealtimeNode.parameters].
  RealtimePath parameter(String name) =>
      RealtimePath._([..._parts, _Parameter(name)]);
}

/// The values [RealtimeNode.parameters] resolves a branch's placeholders
/// with.
final class RealtimeParameters {
  const RealtimeParameters._(this._values);

  final Map<String, Object> _values;

  /// Supplies [value] for the parameter [RealtimePath.parameter] named
  /// [name].
  RealtimeParameters parameter(String name, Object value) =>
      RealtimeParameters._({..._values, name: value});
}

/// One piece of a [RealtimeNode]'s address, either fixed text or a value
/// [RealtimeNode.parameters] has not resolved yet.
sealed class _PathPart {}

/// A piece of text this SDK's own author wrote, through [RealtimePath.segment].
final class _Literal extends _PathPart {
  _Literal(this.value);

  final String value;
}

/// A placeholder [RealtimeNode.parameters] resolves, named through
/// [RealtimePath.parameter].
final class _Parameter extends _PathPart {
  _Parameter(this.name);

  final String name;
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
