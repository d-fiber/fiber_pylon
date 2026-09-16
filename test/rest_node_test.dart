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
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

enum _Signal { notFound, duplicateCall, unknown }

RestClient<_Signal> _client({required http.Client http}) => RestClient<_Signal>(
  baseUrl: Uri.parse('https://api.example.test/v1/'),
  classifier: const _Classifier(),
  guard: CallGuard<_Signal>(duplicateSignal: _Signal.duplicateCall),
  httpClient: http,
);

class _Classifier implements RestClassifier<_Signal> {
  const _Classifier();

  @override
  _Signal? ofResponse(RestResponse response) =>
      response.status == 404 ? _Signal.notFound : null;

  @override
  _Signal ofTransport(Object error, StackTrace stackTrace) => _Signal.unknown;
}

const _mapper = FaultMapper<_Signal, String>(
  signals: {_Signal.notFound: 'not-found'},
  fallback: 'unknown',
);

http.Response _jsonResponseWithContentType(String body, {int status = 200}) =>
    http.Response(body, status, headers: {'content-type': 'application/json'});

void main() {
  group('RestNode.node', () {
    test('composes several literal segments separated by /', () {
      final client = _client(
        http: MockClient((_) async => http.Response('', 200)),
      );
      final endpoint = RestNode<_Signal>.root(
        client,
      ).node('v1/store').node('status').url();
      expect(endpoint.path, 'v1/store/status');
    });

    test('rejects a literal segment equal to "." or ".."', () {
      final client = _client(
        http: MockClient((_) async => http.Response('', 200)),
      );
      final root = RestNode<_Signal>.root(client);

      expect(() => root.node('..'), throwsArgumentError);
      expect(() => root.node('store/..'), throwsArgumentError);
      expect(() => root.node('.'), throwsArgumentError);
    });
  });

  group('RestNode.value', () {
    test('never splits an external value on /', () {
      final client = _client(
        http: MockClient((_) async => http.Response('', 200)),
      );
      final endpoint = RestNode<_Signal>.root(
        client,
      ).node('store').value('a/b').url();
      expect(endpoint.path, 'store/a%2Fb');
    });

    test('encodes a value that tries to inject a query string', () {
      final client = _client(
        http: MockClient((_) async => http.Response('', 200)),
      );
      final endpoint = RestNode<_Signal>.root(
        client,
      ).node('store').value('7?admin=true').url();
      expect(endpoint.path, 'store/7%3Fadmin%3Dtrue');
    });

    test('a resolved call never escapes the node it was composed under, '
        'proven against the real RestClient resolution', () async {
      Uri? requested;
      final client = _client(
        http: MockClient((request) async {
          requested = request.url;
          return http.Response('{}', 200);
        }),
      );
      final endpoint = RestNode<_Signal>.root(
        client,
      ).node('store').value('../../admin/secret').url();

      await endpoint.get(mapper: _mapper, decode: (r) => r.body);

      expect(requested, isNotNull);
      expect(requested!.path, startsWith('/v1/store/'));
      expect(requested!.queryParameters, isEmpty);
    });

    test('rejects a value strictly equal to "." or ".."', () {
      final client = _client(
        http: MockClient((_) async => http.Response('', 200)),
      );
      final root = RestNode<_Signal>.root(client).node('store');

      expect(() => root.value('..'), throwsArgumentError);
      expect(() => root.value('.'), throwsArgumentError);
    });

    test('a numeric value next to the rejected "." and ".." keeps the '
        'preceding segment intact, proven against the real RestClient '
        'resolution', () async {
      Uri? requested;
      final client = _client(
        http: MockClient((request) async {
          requested = request.url;
          return http.Response('{}', 200);
        }),
      );
      final endpoint = RestNode<_Signal>.root(
        client,
      ).node('store').value('7').url();

      await endpoint.get(mapper: _mapper, decode: (r) => r.body);

      expect(requested!.path, '/v1/store/7');
    });
  });

  group('RestEndpoint.get sharing', () {
    test('two concurrent reads at the same path and query coalesce into one '
        'HTTP call', () async {
      var calls = 0;
      final client = _client(
        http: MockClient((request) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return _jsonResponseWithContentType('{"page":1}');
        }),
      );
      final endpoint = RestNode<_Signal>.root(client).node('store').url();

      final first = endpoint.get(mapper: _mapper, decode: (r) => r.map);
      final second = endpoint.get(mapper: _mapper, decode: (r) => r.map);
      final results = await Future.wait([first, second]);

      expect(calls, 1);
      expect(results[0], results[1]);
    });

    test('two concurrent reads of the same path but a different cursor do not '
        'coalesce, and each gets its own page — the pagination bug found '
        'during the design debate', () async {
      var calls = 0;
      final client = _client(
        http: MockClient((request) async {
          calls++;
          final cursor = request.url.queryParameters['cursor'];
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return _jsonResponseWithContentType('{"cursor":"$cursor"}');
        }),
      );
      final endpoint = RestNode<_Signal>.root(
        client,
      ).node('store').node('sync').url();

      final first = endpoint.get(
        query: {'cursor': 'a'},
        mapper: _mapper,
        decode: (r) => r.map['cursor'],
      );
      final second = endpoint.get(
        query: {'cursor': 'b'},
        mapper: _mapper,
        decode: (r) => r.map['cursor'],
      );
      final results = await Future.wait([first, second]);

      expect(calls, 2);
      expect(results.map((r) => r.dataOrNull), ['a', 'b']);
    });
  });

  group('RestEndpoint mutation deduplication', () {
    test('a second POST with an identical body, fired while the first is in '
        'flight, is refused rather than sent', () async {
      var calls = 0;
      final client = _client(
        http: MockClient((request) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return _jsonResponseWithContentType('{"id":"1"}');
        }),
      );
      final endpoint = RestNode<_Signal>.root(client).node('store').url();

      final first = endpoint.post(
        body: {'title': 'Acme'},
        mapper: _mapper,
        decode: (r) => r.map,
      );
      final second = endpoint.post(
        body: {'title': 'Acme'},
        mapper: _mapper,
        decode: (r) => r.map,
      );
      final results = await Future.wait([first, second]);

      expect(calls, 1);
      expect(results[1].isFailure, isTrue);
    });

    test('two POSTs with different bodies on the same path both go through — '
        'the mutation-key bug found during the design debate', () async {
      var calls = 0;
      final client = _client(
        http: MockClient((request) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return _jsonResponseWithContentType('{"id":"$calls"}');
        }),
      );
      final endpoint = RestNode<_Signal>.root(client).node('store').url();

      final first = endpoint.post(
        body: {'title': 'Acme'},
        mapper: _mapper,
        decode: (r) => r.map,
      );
      final second = endpoint.post(
        body: {'title': 'Other'},
        mapper: _mapper,
        decode: (r) => r.map,
      );
      final results = await Future.wait([first, second]);

      expect(calls, 2);
      expect(results[0].isOk, isTrue);
      expect(results[1].isOk, isTrue);
    });

    test('two bodies with the same fields in a different insertion order '
        'still collide as one dedup key', () async {
      var calls = 0;
      final client = _client(
        http: MockClient((request) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return _jsonResponseWithContentType('{}');
        }),
      );
      final endpoint = RestNode<_Signal>.root(client).node('store').url();

      final first = endpoint.post(
        body: {'title': 'Acme', 'draft': true},
        mapper: _mapper,
        decode: (r) => r.map,
      );
      final second = endpoint.post(
        body: {'draft': true, 'title': 'Acme'},
        mapper: _mapper,
        decode: (r) => r.map,
      );
      final results = await Future.wait([first, second]);

      expect(calls, 1);
      expect(results[1].isFailure, isTrue);
    });
  });

  group('CallKey.share on a mutating verb', () {
    test('a POST whose real semantics are a shared read coalesces under an '
        'explicit share key — the brand/sync case found during the design '
        'debate', () async {
      var calls = 0;
      final client = _client(
        http: MockClient((request) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return _jsonResponseWithContentType('{"page":1}');
        }),
      );
      final endpoint = RestNode<_Signal>.root(
        client,
      ).node('store').node('sync').url();

      final first = endpoint.post(
        body: {'cursor': 'a'},
        key: const CallKey.share('store/sync/a'),
        mapper: _mapper,
        decode: (r) => r.map,
      );
      final second = endpoint.post(
        body: {'cursor': 'a'},
        key: const CallKey.share('store/sync/a'),
        mapper: _mapper,
        decode: (r) => r.map,
      );
      final results = await Future.wait([first, second]);

      expect(calls, 1);
      expect(results[0], results[1]);
    });
  });
}
