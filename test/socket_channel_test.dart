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

import 'package:flutter_test/flutter_test.dart';
import 'package:fiber_pylon/fiber_pylon.dart';

class FakeLink implements SocketLink {
  final StreamController<String> _inbound =
      StreamController<String>.broadcast();
  final List<String> sent = [];
  bool closed = false;
  bool refuseSend = false;

  @override
  Stream<String> get inbound => _inbound.stream;

  @override
  void send(String frame) {
    if (refuseSend) throw StateError('gone');
    sent.add(frame);
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!_inbound.isClosed) await _inbound.close();
  }

  void deliver(String frame) => _inbound.add(frame);

  void drop() {
    if (!_inbound.isClosed) _inbound.close();
  }
}

class LineProtocol implements SocketProtocol<String> {
  final List<FakeLink> opened = [];
  int endpointCalls = 0;

  @override
  Future<Uri> endpoint() async {
    endpointCalls++;
    return Uri.parse('wss://house.test/socket');
  }

  @override
  String encodeJoin(String name, int reference) => 'join:$name:$reference';

  @override
  String encodeLeave(
    String name, {
    required int joinReference,
    required int reference,
  }) => 'leave:$name:$joinReference:$reference';

  @override
  String encodeHeartbeat(int reference) => 'beat:$reference';

  @override
  SocketFrame<String> decode(String raw, Map<int, String> references) {
    final parts = raw.split(':');
    return switch (parts.first) {
      'ok' => SocketJoined<String>(references[int.parse(parts[1])] ?? ''),
      'no' => SocketRejected<String>(
        references[int.parse(parts[1])] ?? '',
        parts.length > 2 ? parts[2] : null,
      ),
      'event' => SocketEvent<String>(parts[1]),
      _ => const SocketIgnored<String>(),
    };
  }
}

typedef Harness = ({
  SocketChannel<String> channel,
  LineProtocol protocol,
  List<FakeLink> links,
});

Harness harnessed({
  Duration heartbeat = const Duration(milliseconds: 20),
  Duration silence = const Duration(milliseconds: 60),
}) {
  final protocol = LineProtocol();
  final links = <FakeLink>[];
  final channel = SocketChannel<String>(
    protocol: protocol,
    opener: (endpoint) async {
      final link = FakeLink();
      links.add(link);
      return link;
    },
    heartbeatInterval: heartbeat,
    silence: silence,
  );
  return (channel: channel, protocol: protocol, links: links);
}

void main() {
  group('SocketChannel', () {
    test('reports open once the link is up', () async {
      final harness = harnessed();
      final seen = <ChannelState>[];
      harness.channel.state.listen(seen.add);

      await harness.channel.open();
      await pumpEventQueue();

      expect(seen, [ChannelState.opening, ChannelState.open]);
      await harness.channel.dispose();
    });

    test('opens one link when asked twice at once', () async {
      final harness = harnessed();

      await Future.wait([harness.channel.open(), harness.channel.open()]);

      expect(harness.links, hasLength(1));
      expect(harness.protocol.endpointCalls, 1);
      await harness.channel.dispose();
    });

    test('sends the join frame the protocol built', () async {
      final harness = harnessed();
      await harness.channel.open();

      await harness.channel.join('brands');

      expect(harness.links.single.sent, ['join:brands:1']);
      await harness.channel.dispose();
    });

    test('counts a name as joined only once the server confirms it', () async {
      final harness = harnessed();
      await harness.channel.open();
      await harness.channel.join('brands');

      expect(harness.channel.confirmed, isEmpty);

      harness.links.single.deliver('ok:1');
      await pumpEventQueue();

      expect(harness.channel.confirmed, {'brands'});
      await harness.channel.dispose();
    });

    test(
      'leaves a refused name unconfirmed instead of assuming it worked',
      () async {
        final harness = harnessed();
        await harness.channel.open();
        await harness.channel.join('brands');

        harness.links.single.deliver('no:1:denied');
        await pumpEventQueue();

        expect(harness.channel.confirmed, isEmpty);
        await harness.channel.dispose();
      },
    );

    test('publishes the events the protocol decoded', () async {
      final harness = harnessed();
      final seen = <String>[];
      harness.channel.events.listen(seen.add);
      await harness.channel.open();

      harness.links.single.deliver('event:brand-changed');
      await pumpEventQueue();

      expect(seen, ['brand-changed']);
      await harness.channel.dispose();
    });

    test('addresses a leave with the reference its join used', () async {
      final harness = harnessed();
      await harness.channel.open();
      await harness.channel.join('brands');
      harness.links.single.sent.clear();

      await harness.channel.leave('brands');

      expect(harness.links.single.sent, ['leave:brands:1:2']);
      await harness.channel.dispose();
    });

    test('sends a heartbeat on its own schedule', () async {
      final harness = harnessed();
      await harness.channel.open();

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        harness.links.single.sent.where((frame) => frame.startsWith('beat:')),
        isNotEmpty,
      );
      await harness.channel.dispose();
    });

    test('drops a link that has gone quiet without closing', () async {
      final harness = harnessed();
      final seen = <ChannelState>[];
      harness.channel.state.listen(seen.add);
      await harness.channel.open();

      await Future<void>.delayed(const Duration(milliseconds: 90));

      expect(seen.last, ChannelState.closed);
      expect(harness.links.single.closed, isTrue);
      await harness.channel.dispose();
    });

    test('keeps a link that answers alive', () async {
      final harness = harnessed();
      final seen = <ChannelState>[];
      harness.channel.state.listen(seen.add);
      await harness.channel.open();

      for (var tick = 0; tick < 5; tick++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        harness.links.single.deliver('pong');
      }

      expect(seen, isNot(contains(ChannelState.closed)));
      await harness.channel.dispose();
    });

    test('reports closed when the link goes away', () async {
      final harness = harnessed();
      final seen = <ChannelState>[];
      harness.channel.state.listen(seen.add);
      await harness.channel.open();

      harness.links.single.drop();
      await pumpEventQueue();

      expect(seen.last, ChannelState.closed);
      await harness.channel.dispose();
    });

    test('forgets what was confirmed once the link is gone', () async {
      final harness = harnessed();
      await harness.channel.open();
      await harness.channel.join('brands');
      harness.links.single.deliver('ok:1');
      await pumpEventQueue();

      harness.links.single.drop();
      await pumpEventQueue();

      expect(harness.channel.confirmed, isEmpty);
      await harness.channel.dispose();
    });

    test('refuses to join when nothing is open', () async {
      final harness = harnessed();

      await expectLater(harness.channel.join('brands'), throwsStateError);
      await harness.channel.dispose();
    });

    test('surfaces a send that failed instead of losing it', () async {
      final harness = harnessed();
      await harness.channel.open();
      harness.links.single.refuseSend = true;

      await expectLater(harness.channel.join('brands'), throwsStateError);
      await harness.channel.dispose();
    });

    test('survives a frame the protocol cannot decode', () async {
      final protocol = _ThrowingProtocol();
      final links = <FakeLink>[];
      final channel = SocketChannel<String>(
        protocol: protocol,
        opener: (endpoint) async {
          final link = FakeLink();
          links.add(link);
          return link;
        },
        heartbeatInterval: const Duration(milliseconds: 20),
        silence: const Duration(milliseconds: 200),
      );
      final seen = <ChannelState>[];
      channel.state.listen(seen.add);
      await channel.open();

      links.single.deliver('anything');
      await pumpEventQueue();

      expect(seen, isNot(contains(ChannelState.closed)));
      await channel.dispose();
    });

    test('asks the protocol for a fresh endpoint on every open', () async {
      final harness = harnessed();
      await harness.channel.open();
      await harness.channel.close();

      await harness.channel.open();

      expect(harness.protocol.endpointCalls, 2);
      await harness.channel.dispose();
    });
  });
}

class _ThrowingProtocol extends LineProtocol {
  @override
  SocketFrame<String> decode(String raw, Map<int, String> references) =>
      throw const FormatException('unreadable');
}
