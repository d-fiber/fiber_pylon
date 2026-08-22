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

/// The table that turns this adapter's signals into the error [PostPort.read]
/// declares.
///
/// It sits beside the adapter because it translates one server's vocabulary.
/// The DummyJSON adapter has its own, and the contract knows about neither.
const _readPost = FaultMapper<PlaceholderSignal, ReadPostError>(
  signals: {
    PlaceholderSignal.missing: ReadPostError.notFound,
    PlaceholderSignal.refused: ReadPostError.refused,
    PlaceholderSignal.throttled: ReadPostError.tooFast,
    PlaceholderSignal.noRoute: ReadPostError.offline,
    PlaceholderSignal.slow: ReadPostError.offline,
    PlaceholderSignal.duplicate: ReadPostError.unknown,
  },
  fallback: ReadPostError.unknown,
);

const _listPosts = FaultMapper<PlaceholderSignal, ListPostsError>(
  signals: {
    PlaceholderSignal.refused: ListPostsError.refused,
    PlaceholderSignal.throttled: ListPostsError.tooFast,
    PlaceholderSignal.noRoute: ListPostsError.offline,
    PlaceholderSignal.slow: ListPostsError.offline,
    PlaceholderSignal.duplicate: ListPostsError.unknown,
  },
  fallback: ListPostsError.unknown,
);

/// A backend over JSONPlaceholder.
///
/// It carries no credential, which is why its guard is the plain one: only
/// deduplication is left, and there is nothing to renew.
class PlaceholderBackend implements ExampleBackend {
  late final RestClient<PlaceholderSignal> _client;

  @override
  String get name => 'jsonplaceholder';

  @override
  String get describe =>
      'jsonplaceholder.typicode.com, over HTTP. Posts arrive with numeric ids.';

  @override
  PostPort get posts => _PlaceholderPosts(_client);

  @override
  CredentialManager<Object, Object>? get credentials => null;

  @override
  Future<void> initialize() async {
    _client = RestClient<PlaceholderSignal>(
      baseUrl: Uri.parse(_root),
      classifier: const PlaceholderClassifier(),
      guard: CallGuard<PlaceholderSignal>(
        duplicateSignal: PlaceholderSignal.duplicate,
      ),
      timeout: const Duration(seconds: 10),
    );
  }

  @override
  Future<void> dispose() => _client.dispose();
}

class _PlaceholderPosts implements PostPort {
  final RestClient<PlaceholderSignal> _client;

  const _PlaceholderPosts(this._client);

  @override
  Future<ListPostsResult> list() => _listPosts.guard(() async {
    final response = await _client.send(
      const RestRequest(
        path: 'posts',
        query: {'_limit': '10'},
        shareKey: 'posts',
      ),
    );

    return response.list
        .cast<Map<String, dynamic>>()
        .map(PlaceholderPost.fromJson)
        .map((post) => post.toContract())
        .toList();
  });

  @override
  Future<ReadPostResult> read(String id) => _readPost.guard(() async {
    final response = await _client.send(
      RestRequest(path: 'posts/$id', shareKey: 'posts/$id'),
    );

    return PlaceholderPost.fromJson(response.map).toContract();
  });
}
