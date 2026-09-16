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

import 'package:flutter/material.dart';
import 'package:fiber_pylon/fiber_pylon.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pylon_example/backends/memory/memory_backend.dart';
import 'package:pylon_example/contract/contract.dart';
import 'package:pylon_example/posts_sdk.dart';
import 'package:pylon_example/ui/posts_page.dart';

const _posts = [
  Post(id: '1', title: 'First', body: 'One', author: 'someone'),
  Post(id: '2', title: 'Second', body: 'Two'),
];

MemoryBackend Function() backendHolding(List<Post> posts) =>
    () => MemoryBackend(
      posts: List<Post>.of(posts),
      latency: Duration.zero,
      publishEvery: const Duration(days: 1),
    );

Future<void> startWith(List<Post> posts) =>
    PostsSdk.initialize(backend: backendHolding(posts));

Future<void> showPosts(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PostsPage(choices: const ['memory'], onSwitch: (_) {}),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Future<void> unmountAndShutdownSdkViaRealAsyncZone(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(PostsSdk.shutdown);
}

void main() {
  tearDown(() => PostsSdk.shutdown());

  group('MemoryBackend', () {
    test('answers the posts it holds', () async {
      await startWith(_posts);

      final result = await PostsSdk.I.posts.list();

      expect(result, isA<OK<List<Post>, ListPostsError>>());
      expect(result.dataOrNull, hasLength(2));
    });

    test('answers notFound for an identifier it does not hold', () async {
      await startWith(_posts);

      final result = await PostsSdk.I.posts.read('404');

      expect(
        result,
        const Failure<Post, ReadPostError>(ReadPostError.notFound),
      );
    });

    test('holds no credential, and says so', () async {
      await startWith(_posts);

      expect(PostsSdk.I.credentials, isNull);
    });

    test('offers live events', () async {
      await startWith(_posts);

      expect(PostsSdk.I.events, isNotNull);
    });

    test('publishes a post it was not asked for, on its own', () async {
      await PostsSdk.initialize(
        backend: () => MemoryBackend(
          posts: List<Post>.of(_posts),
          latency: Duration.zero,
          publishEvery: const Duration(milliseconds: 20),
        ),
      );

      final first = await PostsSdk.I.events!.newPosts().first;

      expect(first.title, isNotEmpty);
    });
  });

  group('PostsPage', () {
    testWidgets('renders what the port answered', (tester) async {
      await startWith(_posts);
      await showPosts(tester);

      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);

      await unmountAndShutdownSdkViaRealAsyncZone(tester);
    });

    testWidgets('says so when the backend holds nothing', (tester) async {
      await startWith(const []);
      await showPosts(tester);

      expect(find.text('This backend holds no posts.'), findsOneWidget);

      await unmountAndShutdownSdkViaRealAsyncZone(tester);
    });

    testWidgets('shows what the backend describes itself as', (tester) async {
      await startWith(_posts);
      await showPosts(tester);

      expect(find.text(PostsSdk.I.describe), findsOneWidget);

      await unmountAndShutdownSdkViaRealAsyncZone(tester);
    });

    testWidgets('shows a live post the moment it arrives', (tester) async {
      await PostsSdk.initialize(
        backend: () => MemoryBackend(
          posts: List<Post>.of(_posts),
          latency: Duration.zero,
          publishEvery: const Duration(milliseconds: 50),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PostsPage(choices: const ['memory'], onSwitch: (_) {}),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));

      expect(find.textContaining('Listening for live posts'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 60));

      expect(
        find.textContaining('Just arrived: A post arrived'),
        findsOneWidget,
      );

      await unmountAndShutdownSdkViaRealAsyncZone(tester);
    });
  });
}
