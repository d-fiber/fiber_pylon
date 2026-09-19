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

import 'package:fiber_pylon/fiber_pylon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MemoryChannel', () {
    test('delivers a published event to every listener', () async {
      final channel = MemoryChannel<String>();
      final received = <String>[];
      final sub = channel.events.listen(received.add);

      channel.publish('hello');
      await Future<void>.delayed(Duration.zero);

      expect(received, ['hello']);
      await sub.cancel();
      await channel.dispose();
    });

    test('records what was joined and left', () async {
      final channel = MemoryChannel<String>();

      await channel.join('brand:42');
      expect(channel.joined, {'brand:42'});

      await channel.leave('brand:42');
      expect(channel.joined, isEmpty);

      await channel.dispose();
    });

    test('reports open once opened, and closed once closed', () async {
      final channel = MemoryChannel<String>();
      final states = <ChannelState>[];
      final sub = channel.state.listen(states.add);

      await channel.open();
      await channel.close();
      await Future<void>.delayed(Duration.zero);

      expect(states, [ChannelState.open, ChannelState.closed]);
      expect(channel.joined, isEmpty);

      await sub.cancel();
      await channel.dispose();
    });

    test('works as a Channel behind a real ChannelKeeper', () async {
      final channel = MemoryChannel<String>();
      final keeper = ChannelKeeper<String>(channel);
      final received = <String>[];
      final sub = keeper.events.listen(received.add);

      await keeper.start();
      await keeper.join('brand:42');
      await Future<void>.delayed(Duration.zero);

      channel.publish('brand changed');
      await Future<void>.delayed(Duration.zero);

      expect(received, ['brand changed']);
      expect(channel.joined, {'brand:42'});

      await sub.cancel();
      await keeper.dispose();
    });
  });
}
