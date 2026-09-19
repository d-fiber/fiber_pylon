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
import 'dart:math';

import 'package:fiber_pylon/fiber_pylon.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeChannel implements Channel<String> {
  final StreamController<String> _events = StreamController<String>.broadcast();
  final StreamController<ChannelState> _state = StreamController<ChannelState>.broadcast();

  final List<String> joined = [];
  final List<String> left = [];
  int opens = 0;
  int closes = 0;

  @override
  Stream<String> get events => _events.stream;

  @override
  Stream<ChannelState> get state => _state.stream;

  @override
  Future<void> open() async {
    opens++;
    _state.add(ChannelState.open);
  }

  @override
  Future<void> close() async {
    closes++;
    _state.add(ChannelState.closed);
  }

  @override
  Future<void> join(String name) async {
    joined.add(name);
  }

  @override
  Future<void> leave(String name) async {
    left.add(name);
  }

  void drop() => _state.add(ChannelState.closed);

  Future<void> shutdown() async {
    await _events.close();
    await _state.close();
  }
}

Backoff get immediate => Backoff(
  initial: const Duration(milliseconds: 10),
  ceiling: const Duration(milliseconds: 10),
  jitter: 0,
  random: Random(1),
);

void main() {
  group('ChannelKeeper', () {
    test('opens the channel when started', () async {
      final channel = FakeChannel();
      final keeper = ChannelKeeper<String>(channel, backoff: immediate);

      await keeper.start();
      await pumpEventQueue();

      expect(channel.opens, 1);
      expect(keeper.state.value, ChannelState.open);
      await keeper.dispose();
      await channel.shutdown();
    });

    test('joins a name recorded while connected', () async {
      final channel = FakeChannel();
      final keeper = ChannelKeeper<String>(channel, backoff: immediate);
      await keeper.start();
      await pumpEventQueue();

      await keeper.join('brands');

      expect(channel.joined, ['brands']);
      await keeper.dispose();
      await channel.shutdown();
    });

    test('remembers a name recorded before the channel was open', () async {
      final channel = FakeChannel();
      final keeper = ChannelKeeper<String>(channel, backoff: immediate);

      await keeper.join('brands');
      await keeper.start();
      await pumpEventQueue();

      expect(keeper.wanted, {'brands'});
      expect(channel.joined, ['brands']);
      await keeper.dispose();
      await channel.shutdown();
    });

    test('rejoins everything wanted after the connection came back', () async {
      final channel = FakeChannel();
      final keeper = ChannelKeeper<String>(channel, backoff: immediate);
      await keeper.start();
      await pumpEventQueue();
      await keeper.join('brands');
      await keeper.join('stores');
      channel.joined.clear();

      channel.drop();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(channel.opens, 2);
      expect(channel.joined, containsAll(['brands', 'stores']));
      await keeper.dispose();
      await channel.shutdown();
    });

    test('does not rejoin a name that was left', () async {
      final channel = FakeChannel();
      final keeper = ChannelKeeper<String>(channel, backoff: immediate);
      await keeper.start();
      await pumpEventQueue();
      await keeper.join('brands');
      await keeper.leave('brands');
      channel.joined.clear();

      channel.drop();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(keeper.wanted, isEmpty);
      expect(channel.joined, isEmpty);
      await keeper.dispose();
      await channel.shutdown();
    });

    test('reconnect closes and reopens while keeping every name', () async {
      final channel = FakeChannel();
      final keeper = ChannelKeeper<String>(channel, backoff: immediate);
      await keeper.start();
      await pumpEventQueue();
      await keeper.join('brands');
      channel.joined.clear();

      await keeper.reconnect();
      await pumpEventQueue();

      expect(channel.closes, greaterThanOrEqualTo(1));
      expect(channel.joined, ['brands']);
      await keeper.dispose();
      await channel.shutdown();
    });

    test('opens exactly once more when asked to reconnect', () async {
      final channel = FakeChannel();
      final keeper = ChannelKeeper<String>(channel, backoff: immediate);
      await keeper.start();
      await pumpEventQueue();

      await keeper.reconnect();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(channel.opens, 2);
      await keeper.dispose();
      await channel.shutdown();
    });

    test('stops reopening once disposed', () async {
      final channel = FakeChannel();
      final keeper = ChannelKeeper<String>(channel, backoff: immediate);
      await keeper.start();
      await pumpEventQueue();

      await keeper.dispose();
      final opensAtDispose = channel.opens;
      channel.drop();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(channel.opens, opensAtDispose);
      await channel.shutdown();
    });
  });
}
