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
import 'package:pylon_example/ui/posts_page.dart';

const _posts = [
  Post(id: '1', title: 'First', body: 'One', author: 'someone'),
  Post(id: '2', title: 'Second', body: 'Two'),
];

MemoryBackend backendHolding(List<Post> posts) =>
    MemoryBackend(posts: posts, latency: Duration.zero);

Future<void> showPosts(WidgetTester tester, ExampleBackend backend) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PostsPage(
        backend: backend,
        choices: const ['memory'],
        onSwitch: (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('MemoryBackend', () {
    test('answers the posts it holds', () async {
      final backend = backendHolding(_posts);

      final result = await backend.posts.list();

      expect(result, isA<OK<List<Post>, ListPostsError>>());
      expect(result.dataOrNull, hasLength(2));
    });

    test('answers notFound for an identifier it does not hold', () async {
      final backend = backendHolding(_posts);

      final result = await backend.posts.read('404');

      expect(
        result,
        const Failure<Post, ReadPostError>(ReadPostError.notFound),
      );
    });

    test('holds no credential, and says so', () {
      expect(backendHolding(_posts).credentials, isNull);
    });
  });

  group('PostsPage', () {
    testWidgets('renders what the port answered', (tester) async {
      await showPosts(tester, backendHolding(_posts));

      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
    });

    testWidgets('says so when the backend holds nothing', (tester) async {
      await showPosts(tester, backendHolding(const []));

      expect(find.text('This backend holds no posts.'), findsOneWidget);
    });

    testWidgets('shows what the backend describes itself as', (tester) async {
      final backend = backendHolding(_posts);

      await showPosts(tester, backend);

      expect(find.text(backend.describe), findsOneWidget);
    });
  });
}
