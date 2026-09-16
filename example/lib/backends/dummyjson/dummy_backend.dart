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
import 'package:http/http.dart' as http;

import '../../contract/contract.dart';
import 'classifier.dart';
import 'post_dto.dart';
import 'refresher.dart';
import 'session.dart';
import 'signals.dart';

/// Where DummyJSON lives.
const _root = 'https://dummyjson.com/';

/// The account DummyJSON publishes for anyone to try its sandbox with.
///
/// Fine to hold in the open because that is what it is for. A real adapter reads
/// this from wherever the app keeps its secrets, and pylon never sees it either
/// way.
const _demoUser = 'emilys';
const _demoPassword = 'emilyspass';

/// How long a token lasts.
///
/// A minute, so that the renewal actually happens while somebody is looking at
/// the screen. Production asks for an hour, and the policy is identical.
const _lifetime = Duration(minutes: 1);

/// How long before expiry the renewal starts, which must be shorter than
/// [_lifetime] or every token looks stale the moment it arrives.
const _buffer = Duration(seconds: 20);

const _readPost = FaultMapper<DummySignal, ReadPostError>(
  signals: {
    DummySignal.unknownPost: ReadPostError.notFound,
    DummySignal.denied: ReadPostError.refused,
    DummySignal.tooMany: ReadPostError.tooFast,
    DummySignal.unreachable: ReadPostError.offline,
    DummySignal.timedOut: ReadPostError.offline,
    DummySignal.duplicated: ReadPostError.unknown,
  },
  fallback: ReadPostError.unknown,
);

const _listPosts = FaultMapper<DummySignal, ListPostsError>(
  signals: {
    DummySignal.denied: ListPostsError.refused,
    DummySignal.tooMany: ListPostsError.tooFast,
    DummySignal.unreachable: ListPostsError.offline,
    DummySignal.timedOut: ListPostsError.offline,
    DummySignal.duplicated: ListPostsError.unknown,
  },
  fallback: ListPostsError.unknown,
);

/// A backend over DummyJSON, with a credential it keeps alive.
///
/// Worth comparing with the JSONPlaceholder one next door. Different server,
/// different failure vocabulary, different body shapes, a credential where the
/// other has none, and the same [PostPort] out the other end. Neither can
/// push, so both answer `null` for [events].
class DummyBackend implements ExampleBackend {
  late final CredentialManager<DummySession, DummySignal> _credentials;
  late final RestClient<DummySignal> _client;
  late final RestClient<DummySignal> _plainClient;
  late final RestNode<DummySignal> _api;
  late final RestNode<DummySignal> _plainApi;
  final http.Client _http = http.Client();

  @override
  String get name => 'dummyjson';

  @override
  String get describe =>
      'dummyjson.com, over HTTP, holding a token that expires in a minute.';

  @override
  PostPort get posts => _DummyPosts(_api.node('posts'));

  @override
  EventsPort? get events => null;

  @override
  CredentialManager<Object, Object> get credentials => _credentials;

  @override
  Future<void> initialize() async {
    _plainClient = RestClient<DummySignal>(
      baseUrl: Uri.parse(_root),
      classifier: const DummyClassifier(),
      guard: CallGuard<DummySignal>(duplicateSignal: DummySignal.duplicated),
      httpClient: _http,
      timeout: const Duration(seconds: 10),
    );
    _plainApi = RestNode<DummySignal>.root(_plainClient);

    _credentials = CredentialManager<DummySession, DummySignal>(
      store: MemoryCredentialStore<DummySession>(),
      refresher: DummyRefresher(_plainApi, _lifetime),
      expiresAt: (session) => session.expiresAt,
      fatalSignals: const {DummySignal.denied},
      buffer: _buffer,
    );

    _client = RestClient<DummySignal>(
      baseUrl: Uri.parse(_root),
      classifier: const DummyClassifier(),
      guard: CallGuard<DummySignal>.renewing(
        duplicateSignal: DummySignal.duplicated,
        credentials: _credentials,
        renewOn: const {DummySignal.denied},
      ),
      headers: (request) async {
        final session = _credentials.credential;
        if (session == null) return const {};
        return {'authorization': 'Bearer ${session.accessToken}'};
      },
      httpClient: _http,
      timeout: const Duration(seconds: 10),
    );
    _api = RestNode<DummySignal>.root(_client);

    await _credentials.start();
    await _signIn();
  }

  @override
  Future<void> dispose() async {
    await _credentials.dispose();
    await _client.dispose();
    await _plainClient.dispose();
    _http.close();
  }

  Future<void> _signIn() async {
    final session = await _plainApi
        .node('auth/login')
        .url()
        .post(
          mapper: _signInMapper,
          authenticated: false,
          body: {
            'username': _demoUser,
            'password': _demoPassword,
            'expiresInMins': _lifetime.inMinutes,
          },
          decode: (r) => DummySession.fromJson(r.map, lifetime: _lifetime),
        );

    switch (session) {
      case OK(:final data):
        await _credentials.grant(data);
      case Failure(:final error):
        throw StateError('DummyJSON refused the demo sign-in: $error');
    }
  }
}

const _signInMapper = FaultMapper<DummySignal, DummySignal>(
  fallback: DummySignal.unaccounted,
);

class _DummyPosts implements PostPort {
  final RestNode<DummySignal> _posts;

  const _DummyPosts(this._posts);

  @override
  Future<ListPostsResult> list() => _posts.url().get(
    query: const {'limit': '10'},
    mapper: _listPosts,
    decode: (r) => (r.map['posts'] as List<Object?>)
        .cast<Map<String, dynamic>>()
        .map(DummyPost.fromJson)
        .map((post) => post.toContract())
        .toList(),
  );

  @override
  Future<ReadPostResult> read(String id) => _posts
      .value(id)
      .url()
      .get(
        mapper: _readPost,
        decode: (r) => DummyPost.fromJson(r.map).toContract(),
      );
}
