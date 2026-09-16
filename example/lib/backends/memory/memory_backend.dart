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

import '../../contract/contract.dart';

/// A backend that answers from a list held in memory, and pushes a new post
/// on a timer instead of waiting for a real server to have one.
///
/// It exists to prove the barrier holds. If the screen works against this, the
/// screen depends on the contract and on nothing else, and no amount of reading
/// the code demonstrates that as well as running it.
///
/// It is also what a test of the layer above runs against, since it needs no
/// network and answers the same way every time.
class MemoryBackend implements ExampleBackend {
  final List<Post> _posts;
  final Duration _latency;
  final Duration _publishEvery;

  final MemoryChannel<Post> _channel = MemoryChannel<Post>();
  late final ChannelKeeper<Post> _keeper;
  late final RealtimeNode<Post> _realtime;
  Timer? _publisher;
  int _nextId = 100;

  /// Answers [posts], after [latency] so that a loading state is visible, and
  /// simulates a new post arriving every [publishEvery].
  MemoryBackend({
    List<Post>? posts,
    Duration latency = const Duration(milliseconds: 300),
    Duration publishEvery = const Duration(seconds: 6),
  }) : _posts = posts ?? _sample,
       _latency = latency,
       _publishEvery = publishEvery;

  @override
  String get name => 'memory';

  @override
  String get describe =>
      'Three posts held in memory. No network at all, and a new one arrives '
      'on its own every ${_publishEvery.inSeconds}s.';

  @override
  PostPort get posts => _MemoryPosts(_posts, _latency);

  @override
  EventsPort get events => _MemoryEvents(_realtime);

  @override
  CredentialManager<Object, Object>? get credentials => null;

  @override
  Future<void> initialize() async {
    _keeper = ChannelKeeper<Post>(_channel);
    _realtime = RealtimeNode<Post>.root(
      keeper: _keeper,
      name: (segments) => segments.join(':'),
      belongsTo: (event, topic) => topic == 'posts',
    );
    await _keeper.start();

    _publisher = Timer.periodic(_publishEvery, (_) => _publishOne());
  }

  @override
  Future<void> dispose() async {
    _publisher?.cancel();
    _publisher = null;
    await _keeper.dispose();
    await _channel.dispose();
  }

  void _publishOne() {
    final post = Post(
      id: '${_nextId++}',
      title: 'A post arrived while you were looking',
      body:
          'Nothing asked for this: memory_backend.dart pushes it on a timer, '
          'the same way a real server would push one over a socket.',
      author: 'memory',
    );
    _posts.insert(0, post);
    _channel.publish(post);
  }
}

class _MemoryPosts implements PostPort {
  final List<Post> _posts;
  final Duration _latency;

  const _MemoryPosts(this._posts, this._latency);

  @override
  Future<ListPostsResult> list() async {
    await Future<void>.delayed(_latency);
    return OK(List<Post>.unmodifiable(_posts));
  }

  @override
  Future<ReadPostResult> read(String id) async {
    await Future<void>.delayed(_latency);
    for (final post in _posts) {
      if (post.id == id) return OK(post);
    }
    return const Failure(ReadPostError.notFound);
  }
}

class _MemoryEvents implements EventsPort {
  final RealtimeNode<Post> _realtime;

  const _MemoryEvents(this._realtime);

  @override
  Stream<Post> newPosts() => _realtime.node('posts').topic().events;
}

const List<Post> _sample = [
  Post(
    id: '1',
    title: 'The wall does not read what crosses it',
    body:
        'A fault carries a signal the adapter named. Pylon transports it and '
        'hands it to a table this project wrote. Nothing in between has an '
        'opinion about what the signal means.',
    author: 'pylon',
  ),
  Post(
    id: '2',
    title: 'Policy belongs to the wall, calls belong to the backend',
    body:
        'Renewing ahead of expiry, collapsing simultaneous attempts, replaying '
        'once after a renewal: written once, and not again by the second '
        'backend.',
    author: 'pylon',
  ),
  Post(
    id: '3',
    title: 'Unplug one, plug the other',
    body:
        'This screen reads PostsSdk.I. Which backend answers is a line in '
        'main.dart, and the screen has no way to find out.',
    author: 'pylon',
  ),
];
