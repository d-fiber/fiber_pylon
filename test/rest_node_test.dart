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

import 'dart:convert';
import 'dart:typed_data';

import 'package:fiber_pylon/fiber_pylon.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

enum _Signal { notFound, duplicateCall, unknown }

RestClient<_Signal> _client({
  required http.Client http,
  RestHeaders? headers,
}) => RestClient<_Signal>(
  baseUrl: Uri.parse('https://api.example.test/v1/'),
  classifier: const _Classifier(),
  guard: CallGuard<_Signal>(duplicateSignal: _Signal.duplicateCall),
  httpClient: http,
  headers: headers,
);

class _Classifier implements RestClassifier<_Signal> {
  const _Classifier();

  @override
  _Signal? ofResponse(RestResponse response) =>
      response.status == 404 ? _Signal.notFound : null;

  @override
  _Signal ofTransport(Object error, StackTrace stackTrace) => _Signal.unknown;
}

http.Response _jsonResponseWithContentType(String body, {int status = 200}) =>
    http.Response(body, status, headers: {'content-type': 'application/json'});

void main() {
  group('RestNode.path with a literal', () {
    test('composes several literal segments separated by /', () {
      final client = _client(
        http: MockClient((_) async => http.Response('', 200)),
      );
      final node = RestNode<_Signal>(
        client,
      ).path((p) => p.segment('v1/store')).path((p) => p.segment('status'));
      expect(node.resolvedPath, 'v1/store/status');
    });

    test('rejects a literal segment equal to "." or ".."', () {
      final client = _client(
        http: MockClient((_) async => http.Response('', 200)),
      );
      final root = RestNode<_Signal>(client);

      expect(() => root.path((p) => p.segment('..')), throwsArgumentError);
      expect(
        () => root.path((p) => p.segment('store/..')),
        throwsArgumentError,
      );
      expect(() => root.path((p) => p.segment('.')), throwsArgumentError);
    });
  });

  group('RestNode.parameters', () {
    test('never splits an external value on /', () {
      final client = _client(
        http: MockClient((_) async => http.Response('', 200)),
      );
      final node = RestNode<_Signal>(client)
          .path((p) => p.segment('store').parameter('id'))
          .parameters((p) => p.parameter('id', 'a/b'));
      expect(node.resolvedPath, 'store/a%2Fb');
    });

    test('encodes a value that tries to inject a query string', () {
      final client = _client(
        http: MockClient((_) async => http.Response('', 200)),
      );
      final node = RestNode<_Signal>(client)
          .path((p) => p.segment('store').parameter('id'))
          .parameters((p) => p.parameter('id', '7?admin=true'));
      expect(node.resolvedPath, 'store/7%3Fadmin%3Dtrue');
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
      final node = RestNode<_Signal>(client)
          .path((p) => p.segment('store').parameter('id'))
          .parameters((p) => p.parameter('id', '../../admin/secret'));

      await node.get().send();

      expect(requested, isNotNull);
      expect(requested!.path, startsWith('/v1/store/'));
      expect(requested!.queryParameters, isEmpty);
    });

    test('rejects a value strictly equal to "." or ".."', () {
      final client = _client(
        http: MockClient((_) async => http.Response('', 200)),
      );
      final store = RestNode<_Signal>(
        client,
      ).path((p) => p.segment('store').parameter('id'));

      expect(
        () => store.parameters((p) => p.parameter('id', '..')),
        throwsArgumentError,
      );
      expect(
        () => store.parameters((p) => p.parameter('id', '.')),
        throwsArgumentError,
      );
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
      final node = RestNode<_Signal>(client)
          .path((p) => p.segment('store').parameter('id'))
          .parameters((p) => p.parameter('id', '7'));

      await node.get().send();

      expect(requested!.path, '/v1/store/7');
    });

    test('resolves several placeholders composed across separate path calls '
        'in one values call', () {
      final client = _client(
        http: MockClient((_) async => http.Response('', 200)),
      );
      final node = RestNode<_Signal>(client)
          .path((p) => p.segment('city').parameter('id').segment('review'))
          .path((p) => p.parameter('reviewId'))
          .parameters(
            (p) => p.parameter('id', '7').parameter('reviewId', '42'),
          );

      expect(node.resolvedPath, 'city/7/review/42');
    });

    test('throws naming the placeholder a call left unresolved', () {
      final client = _client(
        http: MockClient((_) async => http.Response('', 200)),
      );
      final store = RestNode<_Signal>(
        client,
      ).path((p) => p.segment('store').parameter('id'));

      expect(() => store.parameters((p) => p), throwsArgumentError);
    });

    test('throws naming a value nothing in the path asked for', () {
      final client = _client(
        http: MockClient((_) async => http.Response('', 200)),
      );
      final store = RestNode<_Signal>(
        client,
      ).path((p) => p.segment('store').parameter('id'));

      expect(
        () => store.parameters(
          (p) => p.parameter('id', '7').parameter('extra', 'unused'),
        ),
        throwsArgumentError,
      );
    });

    test('sending a call whose placeholder was never resolved throws', () {
      final client = _client(
        http: MockClient((_) async => http.Response('', 200)),
      );
      final store = RestNode<_Signal>(
        client,
      ).path((p) => p.segment('store').parameter('id'));

      expect(store.get, throwsStateError);
    });
  });

  group('RestNode.headers', () {
    test('sends a header set on the node', () async {
      Map<String, String>? seen;
      final client = _client(
        http: MockClient((request) async {
          seen = request.headers;
          return http.Response('', 200);
        }),
      );
      final node = RestNode<_Signal>(client)
          .path((p) => p.segment('store'))
          .headers((h) => h.add('x-app-key', 'demo'));

      await node.get().send();

      expect(seen!['x-app-key'], 'demo');
    });

    test('overrides a header of the same name the client attaches to every '
        'call', () async {
      Map<String, String>? seen;
      final client = _client(
        http: MockClient((request) async {
          seen = request.headers;
          return http.Response('', 200);
        }),
        headers: (request) async => {'x-app-key': 'from-client'},
      );
      final node = RestNode<_Signal>(client)
          .path((p) => p.segment('store'))
          .headers((h) => h.add('x-app-key', 'from-node'));

      await node.get().send();

      expect(seen!['x-app-key'], 'from-node');
    });

    test('a header set further down a chain overrides one a node higher up '
        'already carried', () async {
      Map<String, String>? seen;
      final client = _client(
        http: MockClient((request) async {
          seen = request.headers;
          return http.Response('', 200);
        }),
      );
      final api = RestNode<_Signal>(
        client,
      ).headers((h) => h.add('x-app-key', 'root'));
      final store = api
          .path((p) => p.segment('store'))
          .headers((h) => h.add('x-app-key', 'store'));

      await store.get().send();

      expect(seen!['x-app-key'], 'store');
    });

    test('two otherwise identical GETs asking for different headers do not '
        'coalesce', () async {
      var calls = 0;
      final client = _client(
        http: MockClient((request) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return _jsonResponseWithContentType('{}');
        }),
      );
      final node = RestNode<_Signal>(client).path((p) => p.segment('store'));

      final first = node
          .headers((h) => h.add('accept-language', 'fr'))
          .get()
          .send();
      final second = node
          .headers((h) => h.add('accept-language', 'en'))
          .get()
          .send();
      await Future.wait([first, second]);

      expect(calls, 2);
    });
  });

  group('RestNode.unauthenticated', () {
    test('two otherwise identical GETs, one authenticated and one not, do '
        'not coalesce', () async {
      var calls = 0;
      final client = _client(
        http: MockClient((request) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return _jsonResponseWithContentType('{}');
        }),
      );
      final node = RestNode<_Signal>(client).path((p) => p.segment('store'));

      final first = node.get().send();
      final second = node.unauthenticated().get().send();
      await Future.wait([first, second]);

      expect(calls, 2);
    });
  });

  group('RestNode.get sharing', () {
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
      final node = RestNode<_Signal>(client).path((p) => p.segment('store'));

      final first = node.get().send();
      final second = node.get().send();
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
      final node = RestNode<_Signal>(
        client,
      ).path((p) => p.segment('store')).path((p) => p.segment('sync'));

      final first =
          (node.get()..queryParameters((p) => p.parameter('cursor', 'a')))
              .send();
      final second =
          (node.get()..queryParameters((p) => p.parameter('cursor', 'b')))
              .send();
      final results = await Future.wait([first, second]);

      expect(calls, 2);
      expect(results.map((r) => r.map['cursor']), ['a', 'b']);
    });
  });

  group('RestNode.head sharing', () {
    test('sends the HEAD method, and two concurrent calls coalesce into one '
        'HTTP call', () async {
      var calls = 0;
      String? method;
      final client = _client(
        http: MockClient((request) async {
          calls++;
          method = request.method;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return http.Response('', 200);
        }),
      );
      final node = RestNode<_Signal>(client).path((p) => p.segment('store'));

      final first = node.head().send();
      final second = node.head().send();
      await Future.wait([first, second]);

      expect(calls, 1);
      expect(method, 'HEAD');
    });
  });

  group('RestNode mutation deduplication', () {
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
      final node = RestNode<_Signal>(client).path((p) => p.segment('store'));

      final first = (node.post()..body((b) => b.value('title', 'Acme'))).send();
      final second = (node.post()..body((b) => b.value('title', 'Acme')))
          .send();

      await expectLater(second, throwsA(isA<Fault<_Signal>>()));
      await first;

      expect(calls, 1);
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
      final node = RestNode<_Signal>(client).path((p) => p.segment('store'));

      final first = (node.post()..body((b) => b.value('title', 'Acme'))).send();
      final second = (node.post()..body((b) => b.value('title', 'Other')))
          .send();
      await Future.wait([first, second]);

      expect(calls, 2);
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
      final node = RestNode<_Signal>(client).path((p) => p.segment('store'));

      final first =
          (node.post()
                ..body((b) => b.value('title', 'Acme').value('draft', true)))
              .send();
      final second =
          (node.post()
                ..body((b) => b.value('draft', true).value('title', 'Acme')))
              .send();

      await expectLater(second, throwsA(isA<Fault<_Signal>>()));
      await first;

      expect(calls, 1);
    });
  });

  group('RestNode mutation deduplication with a multipart body', () {
    test('a second POST carrying the same field and file, fired while the '
        'first is in flight, is refused rather than sent', () async {
      var calls = 0;
      final client = _client(
        http: MockClient((request) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return _jsonResponseWithContentType('{"id":"1"}');
        }),
      );
      final node = RestNode<_Signal>(client).path((p) => p.segment('store'));
      final upload = RestUpload(
        field: 'logo',
        bytes: Uint8List.fromList([1, 2, 3]),
        filename: 'logo.png',
        contentType: 'image/png',
      );

      final first =
          (node.post()..multipart((m) => m.field('title', 'Acme').file(upload)))
              .send();
      final second =
          (node.post()..multipart((m) => m.field('title', 'Acme').file(upload)))
              .send();

      await expectLater(second, throwsA(isA<Fault<_Signal>>()));
      await first;

      expect(calls, 1);
    });
  });

  group('RestCall setters merge across repeated calls', () {
    test('calling body more than once merges rather than replaces', () async {
      String? sentBody;
      final client = _client(
        http: MockClient((request) async {
          sentBody = request.body;
          return _jsonResponseWithContentType('{}');
        }),
      );
      final node = RestNode<_Signal>(client).path((p) => p.segment('store'));

      await (node.post()
            ..body((b) => b.value('title', 'Acme'))
            ..body((b) => b.value('draft', true)))
          .send();

      expect(jsonDecode(sentBody!), {'title': 'Acme', 'draft': true});
    });

    test('calling queryParameters more than once merges rather than '
        'replaces', () async {
      Uri? requested;
      final client = _client(
        http: MockClient((request) async {
          requested = request.url;
          return http.Response('', 200);
        }),
      );
      final node = RestNode<_Signal>(client).path((p) => p.segment('store'));

      await (node.get()
            ..queryParameters((p) => p.parameter('limit', '10'))
            ..queryParameters((p) => p.parameter('offset', '0')))
          .send();

      expect(requested!.queryParameters, {'limit': '10', 'offset': '0'});
    });

    test('calling multipart more than once merges fields and accumulates '
        'files, proven by colliding with an equivalent single call', () async {
      var calls = 0;
      final client = _client(
        http: MockClient((request) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return _jsonResponseWithContentType('{"id":"1"}');
        }),
      );
      final node = RestNode<_Signal>(client).path((p) => p.segment('store'));
      final logo = RestUpload(
        field: 'logo',
        bytes: Uint8List.fromList([1, 2, 3]),
        filename: 'logo.png',
        contentType: 'image/png',
      );
      final banner = RestUpload(
        field: 'banner',
        bytes: Uint8List.fromList([4, 5, 6]),
        filename: 'banner.png',
        contentType: 'image/png',
      );

      final first =
          (node.post()..multipart(
                (m) => m
                    .field('title', 'Acme')
                    .field('draft', 'true')
                    .file(logo)
                    .file(banner),
              ))
              .send();
      final second =
          (node.post()
                ..multipart((m) => m.field('title', 'Acme'))
                ..multipart((m) => m.field('draft', 'true'))
                ..multipart((m) => m.file(logo))
                ..multipart((m) => m.file(banner)))
              .send();

      await expectLater(second, throwsA(isA<Fault<_Signal>>()));
      await first;

      expect(calls, 1);
    });
  });
}
