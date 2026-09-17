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

import '../../contract/contract.dart';
import 'classifier.dart';
import 'post_dto.dart';
import 'signals.dart';

/// Where JSONPlaceholder lives.
const _root = 'https://jsonplaceholder.typicode.com/';

/// The resolver that turns this adapter's signals into the error
/// [PostPort.read] declares.
///
/// It sits beside the adapter because it translates one server's vocabulary.
/// The DummyJSON adapter has its own, and the contract knows about neither.
final _readPost = FaultResolver<PlaceholderSignal, ReadPostError>(
  (signal) => switch (signal) {
    PlaceholderSignal.missing => ReadPostError.notFound,
    PlaceholderSignal.refused => ReadPostError.refused,
    PlaceholderSignal.throttled => ReadPostError.tooFast,
    PlaceholderSignal.noRoute => ReadPostError.offline,
    PlaceholderSignal.slow => ReadPostError.offline,
    PlaceholderSignal.duplicate => ReadPostError.unknown,
    _ => ReadPostError.unknown,
  },
);

final _listPosts = FaultResolver<PlaceholderSignal, ListPostsError>(
  (signal) => switch (signal) {
    PlaceholderSignal.refused => ListPostsError.refused,
    PlaceholderSignal.throttled => ListPostsError.tooFast,
    PlaceholderSignal.noRoute => ListPostsError.offline,
    PlaceholderSignal.slow => ListPostsError.offline,
    PlaceholderSignal.duplicate => ListPostsError.unknown,
    _ => ListPostsError.unknown,
  },
);

/// A backend over JSONPlaceholder.
///
/// It carries no credential, which is why its guard is the plain one: only
/// deduplication is left, and there is nothing to renew. It cannot push
/// either, so [events] answers `null`.
final class PlaceholderBackend extends RestBackendSdk
    implements ExampleBackend {
  late final RestClient<PlaceholderSignal> _client;
  late final RestNode<PlaceholderSignal> _api;

  @override
  String get name => 'jsonplaceholder';

  @override
  String get describe =>
      'jsonplaceholder.typicode.com, over HTTP. Posts arrive with numeric ids.';

  @override
  PostPort get posts => _PlaceholderPosts(_api.path((p) => p.segment('posts')));

  @override
  EventsPort? get events => null;

  @override
  CredentialManager<Object, Object>? get credentials => null;

  @override
  Future<void> initialize() async {
    await super.initialize();
    _client = RestClient<PlaceholderSignal>(
      baseUrl: Uri.parse(_root),
      classifier: const PlaceholderClassifier(),
      guard: CallGuard<PlaceholderSignal>(
        duplicateSignal: PlaceholderSignal.duplicate,
      ),
      timeout: const Duration(seconds: 10),
    );
    _api = RestNode<PlaceholderSignal>(_client);
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
    await _client.dispose();
  }
}

class _PlaceholderPosts implements PostPort {
  final RestNode<PlaceholderSignal> _posts;

  const _PlaceholderPosts(this._posts);

  @override
  Future<ListPostsResult> list() async {
    try {
      final request = _posts.get()
        ..queryParameters((p) => p.parameter('_limit', '10'));
      final response = await request.send();
      final posts = response.list
          .cast<Map<String, dynamic>>()
          .map(PlaceholderPost.fromJson)
          .map((post) => post.toContract())
          .toList();
      return OK(posts);
    } on Fault<PlaceholderSignal> catch (fault) {
      return Failure(_listPosts.call(fault));
    }
  }

  @override
  Future<ReadPostResult> read(String id) async {
    try {
      final response = await _posts
          .path((p) => p.parameter('id'))
          .parameters((p) => p.parameter('id', id))
          .get()
          .send();
      return OK(PlaceholderPost.fromJson(response.map).toContract());
    } on Fault<PlaceholderSignal> catch (fault) {
      return Failure(_readPost.call(fault));
    }
  }
}
