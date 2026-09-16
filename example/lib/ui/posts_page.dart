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

import 'package:flutter/material.dart';
import 'package:fiber_pylon/fiber_pylon.dart';

import '../contract/contract.dart';
import '../posts_sdk.dart';

/// The screen, which reads [PostsSdk.I] and has no way to learn which backend
/// answers it.
///
/// Everything it renders comes from the contract: a [Post], or one of the
/// errors the contract declares. There is no status code here, no JSON, and
/// no name of a server.
class PostsPage extends StatefulWidget {
  /// Asks for another backend to be put in place.
  final ValueChanged<String> onSwitch;

  /// The names this app can switch between.
  final List<String> choices;

  /// Shows the posts [PostsSdk.I] holds.
  const PostsPage({required this.onSwitch, required this.choices, super.key});

  @override
  State<PostsPage> createState() => _PostsPageState();
}

class _PostsPageState extends State<PostsPage> {
  ListPostsResult? _result;
  bool _loading = false;
  Post? _lastLive;

  /// Subscribed once in [initState], never from a `StreamBuilder` in
  /// [build]: `build` runs on every unrelated rebuild too, and a
  /// `StreamBuilder` hands back the same last event on each of them, which
  /// would turn one arrival into a post re-added on every keystroke.
  StreamSubscription<Post>? _liveSubscription;

  @override
  void initState() {
    super.initState();
    _load();
    _liveSubscription = PostsSdk.I.events?.newPosts().listen(_onLive);
  }

  @override
  void dispose() {
    _liveSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final result = await PostsSdk.I.posts.list();
    if (!mounted) return;
    setState(() {
      _result = result;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('pylon'),
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Ask again',
        ),
      ],
    ),
    body: Column(
      children: [
        _Switcher(
          current: PostsSdk.I.name,
          choices: widget.choices,
          onSwitch: widget.onSwitch,
        ),
        _Describe(sdk: PostsSdk.I),
        if (PostsSdk.I.events != null) _LiveBanner(last: _lastLive),
        const Divider(height: 1),
        Expanded(child: _body()),
      ],
    ),
  );

  void _onLive(Post post) {
    if (!mounted) return;
    setState(() {
      _lastLive = post;
      final current = _result;
      if (current case OK(:final data)) {
        _result = OK([post, ...data]);
      }
    });
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final result = _result;
    if (result == null) return const SizedBox.shrink();

    return switch (result) {
      OK(:final data) => _PostList(posts: data, justArrived: _lastLive),
      Failure(:final error) => _Trouble(message: _say(error), onRetry: _load),
    };
  }

  static String _say(ListPostsError error) => switch (error) {
    ListPostsError.refused => 'This backend refused the request.',
    ListPostsError.offline => 'This backend could not be reached.',
    ListPostsError.tooFast => 'Too many requests. Wait a moment.',
    ListPostsError.unknown => 'Something went wrong that this app cannot name.',
  };
}

class _Switcher extends StatelessWidget {
  final String current;
  final List<String> choices;
  final ValueChanged<String> onSwitch;

  const _Switcher({
    required this.current,
    required this.choices,
    required this.onSwitch,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: SegmentedButton<String>(
      segments: [
        for (final choice in choices)
          ButtonSegment<String>(value: choice, label: Text(choice)),
      ],
      selected: {current},
      onSelectionChanged: (selection) => onSwitch(selection.first),
    ),
  );
}

class _Describe extends StatelessWidget {
  final PostsSdk sdk;

  const _Describe({required this.sdk});

  @override
  Widget build(BuildContext context) {
    final credentials = sdk.credentials;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(sdk.describe, style: Theme.of(context).textTheme.bodySmall),
          if (credentials != null) ...[
            const SizedBox(height: 6),
            _Credential(credentials: credentials),
          ],
        ],
      ),
    );
  }
}

class _Credential extends StatelessWidget {
  final CredentialManager<Object, Object> credentials;

  const _Credential({required this.credentials});

  @override
  Widget build(BuildContext context) => StreamBuilder<Object?>(
    stream: credentials.changes,
    builder: (context, snapshot) {
      final held = credentials.isHeld;
      final stale = credentials.isStale;

      return Row(
        children: [
          Icon(
            held ? Icons.key : Icons.key_off,
            size: 16,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              held
                  ? stale
                        ? 'Credential held, inside the renewal window'
                        : 'Credential held and fresh'
                  : 'No credential',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: held ? credentials.renew : null,
            child: const Text('Renew now'),
          ),
        ],
      );
    },
  );
}

/// Shown only when [PostsSdk.events] is not `null`: one line naming [last],
/// the post that arrived through [RealtimeTopic.events] rather than a call
/// this screen made.
class _LiveBanner extends StatelessWidget {
  final Post? last;

  const _LiveBanner({required this.last});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: Theme.of(context).colorScheme.secondaryContainer,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      children: [
        const Icon(Icons.podcasts, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            last == null
                ? 'Listening for live posts…'
                : 'Just arrived: ${last!.title}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}

class _PostList extends StatelessWidget {
  final List<Post> posts;
  final Post? justArrived;

  const _PostList({required this.posts, this.justArrived});

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return const Center(child: Text('This backend holds no posts.'));
    }

    return ListView.separated(
      itemCount: posts.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final post = posts[index];
        return ListTile(
          tileColor: post.id == justArrived?.id
              ? Theme.of(context).colorScheme.secondaryContainer
              : null,
          title: Text(post.title),
          subtitle: Text(
            post.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: post.author == null ? null : Text(post.author!),
        );
      },
    );
  }
}

class _Trouble extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _Trouble({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}
