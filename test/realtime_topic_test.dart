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

import 'package:fiber_pylon/fiber_pylon.dart';
import 'package:flutter_test/flutter_test.dart';

class _Event {
  _Event(this.topic, this.payload);

  final String topic;
  final String payload;
}

class _RecordingChannel implements Channel<_Event> {
  final List<String> joinCalls = [];
  final List<String> leaveCalls = [];

  final StreamController<_Event> _events = StreamController.broadcast();
  final StreamController<ChannelState> _state = StreamController.broadcast();

  @override
  Stream<_Event> get events => _events.stream;

  @override
  Stream<ChannelState> get state => _state.stream;

  @override
  Future<void> open() async {
    _state.add(ChannelState.opening);
    _state.add(ChannelState.open);
  }

  @override
  Future<void> close() async {
    _state.add(ChannelState.closed);
  }

  @override
  Future<void> join(String name) async => joinCalls.add(name);

  @override
  Future<void> leave(String name) async => leaveCalls.add(name);

  void emit(_Event event) => _events.add(event);
}

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 5));

RealtimeNode<_Event> _realtime(ChannelKeeper<_Event> keeper) =>
    RealtimeNode<_Event>.root(
      keeper: keeper,
      name: (segments) => segments.join(':'),
      belongsTo: (event, topic) => event.topic == topic,
    );

RealtimeNode<_Event> _brand(ChannelKeeper<_Event> keeper) =>
    _realtime(keeper).path((p) => p.segment('brand').parameter('id'));

void main() {
  group('RealtimeNode.parameters', () {
    test('rejects a value strictly equal to "." or ".."', () async {
      final channel = _RecordingChannel();
      final keeper = ChannelKeeper<_Event>(channel);
      final root = _brand(keeper);

      expect(
        () => root.parameters((p) => p.parameter('id', '..')),
        throwsArgumentError,
      );
      expect(
        () => root.parameters((p) => p.parameter('id', '.')),
        throwsArgumentError,
      );

      await keeper.dispose();
    });

    test('never lets an external value change the joined topic name', () {
      final channel = _RecordingChannel();
      final keeper = ChannelKeeper<_Event>(channel);
      final root = _brand(keeper);

      final topic = root
          .parameters((p) => p.parameter('id', '42:admin'))
          .topic();
      expect(topic.name, 'brand:42%3Aadmin');
    });
  });

  group('two independent subscribers to the same composed topic', () {
    test('share exactly one join on the wire', () async {
      final channel = _RecordingChannel();
      final keeper = ChannelKeeper<_Event>(channel);
      await keeper.start();
      await _flush();

      final realtime = _brand(keeper);
      final received1 = <String>[];
      final received2 = <String>[];

      final sub1 = realtime
          .parameters((p) => p.parameter('id', '42'))
          .topic()
          .events
          .listen((e) => received1.add(e.payload));
      await _flush();
      final sub2 = realtime
          .parameters((p) => p.parameter('id', '42'))
          .topic()
          .events
          .listen((e) => received2.add(e.payload));
      await _flush();

      expect(channel.joinCalls, ['brand:42']);

      channel.emit(_Event('brand:42', 'hello'));
      await _flush();
      expect(received1, ['hello']);
      expect(received2, ['hello']);

      await sub1.cancel();
      await sub2.cancel();
      await keeper.dispose();
    });

    test(
      'the channel is left only once the second subscriber also cancels — '
      'the ChannelKeeper counting bug found during the design debate',
      () async {
        final channel = _RecordingChannel();
        final keeper = ChannelKeeper<_Event>(channel);
        await keeper.start();
        await _flush();

        final realtime = _brand(keeper);
        final sub1 = realtime
            .parameters((p) => p.parameter('id', '42'))
            .topic()
            .events
            .listen((_) {});
        await _flush();
        final sub2 = realtime
            .parameters((p) => p.parameter('id', '42'))
            .topic()
            .events
            .listen((_) {});
        await _flush();

        await sub1.cancel();
        await _flush();
        expect(
          channel.leaveCalls,
          isEmpty,
          reason: 'the second subscriber is still listening',
        );

        await sub2.cancel();
        await _flush();
        expect(channel.leaveCalls, ['brand:42']);

        await keeper.dispose();
      },
    );

    test('a new subscriber after both have cancelled rejoins', () async {
      final channel = _RecordingChannel();
      final keeper = ChannelKeeper<_Event>(channel);
      await keeper.start();
      await _flush();

      final realtime = _brand(keeper);
      final firstSub = realtime
          .parameters((p) => p.parameter('id', '42'))
          .topic()
          .events
          .listen((_) {});
      await _flush();
      await firstSub.cancel();
      await _flush();
      expect(channel.leaveCalls, ['brand:42']);

      final secondSub = realtime
          .parameters((p) => p.parameter('id', '42'))
          .topic()
          .events
          .listen((_) {});
      await _flush();

      expect(channel.joinCalls, ['brand:42', 'brand:42']);

      await secondSub.cancel();
      await keeper.dispose();
    });

    test('an event from a different topic never leaks in', () async {
      final channel = _RecordingChannel();
      final keeper = ChannelKeeper<_Event>(channel);
      await keeper.start();
      await _flush();

      final realtime = _brand(keeper);
      final received = <String>[];
      final sub = realtime
          .parameters((p) => p.parameter('id', '42'))
          .topic()
          .events
          .listen((e) => received.add(e.payload));
      await _flush();

      channel.emit(_Event('brand:99', 'not for us'));
      channel.emit(_Event('brand:42', 'for us'));
      await _flush();

      expect(received, ['for us']);

      await sub.cancel();
      await keeper.dispose();
    });
  });
}
