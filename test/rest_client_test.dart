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
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fiber_pylon/fiber_pylon.dart';

enum HouseSignal {
  unauthorized,
  forbidden,
  vpnRequired,
  notFound,
  nameEmpty,
  timedOut,
  noRoute,
  duplicate,
  unknown,
}

class HouseClassifier implements RestClassifier<HouseSignal> {
  const HouseClassifier();

  @override
  HouseSignal? ofResponse(RestResponse response) {
    if (response.status >= 200 && response.status < 300) return null;

    final body = response.body;
    final code = body is Map<String, dynamic> ? body['code'] : null;
    if (code == 'vpn_required') return HouseSignal.vpnRequired;
    if (code == 'name_empty') return HouseSignal.nameEmpty;

    return switch (response.status) {
      401 => HouseSignal.unauthorized,
      403 => HouseSignal.forbidden,
      404 => HouseSignal.notFound,
      _ => HouseSignal.unknown,
    };
  }

  @override
  HouseSignal ofTransport(Object error, StackTrace stackTrace) =>
      error is TimeoutException ? HouseSignal.timedOut : HouseSignal.noRoute;
}

final Uri houseBase = Uri.parse('https://house.test/v1/admin/');

RestClient<HouseSignal> clientAnswering(
  Future<http.Response> Function(http.Request request) handler, {
  RestHeaders? headers,
  Uri? baseUrl,
}) => RestClient<HouseSignal>(
  baseUrl: baseUrl ?? houseBase,
  classifier: const HouseClassifier(),
  guard: CallGuard<HouseSignal>(duplicateSignal: HouseSignal.duplicate),
  headers: headers,
  httpClient: MockClient(handler),
);

http.Response jsonOk(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  group('RestClient', () {
    test('appends the request path to the base path', () async {
      late Uri seen;
      final client = clientAnswering((request) async {
        seen = request.url;
        return jsonOk({'ok': true});
      });

      await client.send(const RestRequest(path: 'brand/7'));

      expect(seen.toString(), 'https://house.test/v1/admin/brand/7');
      await client.dispose();
    });

    test('ignores a leading slash on the request path', () async {
      late Uri seen;
      final client = clientAnswering((request) async {
        seen = request.url;
        return jsonOk({'ok': true});
      });

      await client.send(const RestRequest(path: '/brand/7'));

      expect(seen.path, '/v1/admin/brand/7');
      await client.dispose();
    });

    test('merges a query written in the path with the query map', () async {
      late Uri seen;
      final client = clientAnswering((request) async {
        seen = request.url;
        return jsonOk({'ok': true});
      });

      await client.send(
        const RestRequest(
          path: 'brand/pagination?offset=20',
          query: {'status': 'draft'},
        ),
      );

      expect(seen.queryParameters, {'offset': '20', 'status': 'draft'});
      await client.dispose();
    });

    test('sends a JSON body and announces it', () async {
      late http.Request seen;
      final client = clientAnswering((request) async {
        seen = request;
        return jsonOk({'ok': true});
      });

      await client.send(
        const RestRequest(
          path: 'brand',
          method: RestMethod.post,
          body: {'name': 'Acme'},
        ),
      );

      expect(seen.method, 'POST');
      expect(seen.body, '{"name":"Acme"}');
      expect(seen.headers['content-type'], contains('application/json'));
      await client.dispose();
    });

    test('returns the decoded body of a successful answer', () async {
      final client = clientAnswering(
        (request) async => jsonOk({
          'data': {'brand_id': '7'},
        }),
      );

      final response = await client.send(const RestRequest(path: 'brand/7'));

      expect(response.status, 200);
      expect(response.map['data'], {'brand_id': '7'});
      await client.dispose();
    });

    test('leaves the body null when the answer was not JSON', () async {
      final client = clientAnswering(
        (request) async => http.Response(
          'plain',
          200,
          headers: {'content-type': 'text/plain'},
        ),
      );

      final response = await client.send(const RestRequest(path: 'ping'));

      expect(response.body, isNull);
      expect(utf8.decode(response.bytes), 'plain');
      await client.dispose();
    });

    test('throws the signal the classifier gave a failing status', () async {
      final client = clientAnswering(
        (request) async => http.Response(
          '{}',
          403,
          headers: {'content-type': 'application/json'},
        ),
      );

      await expectLater(
        client.send(const RestRequest(path: 'brand/7')),
        throwsA(
          isA<Fault<HouseSignal>>().having(
            (fault) => fault.signal,
            'signal',
            HouseSignal.forbidden,
          ),
        ),
      );
      await client.dispose();
    });

    test(
      'lets the classifier read the error body to refine a status',
      () async {
        final client = clientAnswering(
          (request) async => http.Response(
            jsonEncode({'code': 'vpn_required'}),
            403,
            headers: {'content-type': 'application/json'},
          ),
        );

        await expectLater(
          client.send(const RestRequest(path: 'brand/7')),
          throwsA(
            isA<Fault<HouseSignal>>().having(
              (fault) => fault.signal,
              'signal',
              HouseSignal.vpnRequired,
            ),
          ),
        );
        await client.dispose();
      },
    );

    test('carries the error body as the details of the fault', () async {
      final client = clientAnswering(
        (request) async => http.Response(
          jsonEncode({'code': 'name_empty', 'field': 'name'}),
          400,
          headers: {'content-type': 'application/json'},
        ),
      );

      await expectLater(
        client.send(const RestRequest(path: 'brand')),
        throwsA(
          isA<Fault<HouseSignal>>().having(
            (fault) => (fault.details as Map<String, dynamic>)['field'],
            'details.field',
            'name',
          ),
        ),
      );
      await client.dispose();
    });

    test('throws the transport signal when the call never landed', () async {
      final client = clientAnswering(
        (request) async => throw const SocketFailure(),
      );

      await expectLater(
        client.send(const RestRequest(path: 'brand/7')),
        throwsA(
          isA<Fault<HouseSignal>>()
              .having((fault) => fault.signal, 'signal', HouseSignal.noRoute)
              .having((fault) => fault.cause, 'cause', isA<SocketFailure>()),
        ),
      );
      await client.dispose();
    });

    test('distinguishes a timeout from an unreachable host', () async {
      final client = clientAnswering(
        (request) async => throw TimeoutException('too slow'),
      );

      await expectLater(
        client.send(const RestRequest(path: 'brand/7')),
        throwsA(
          isA<Fault<HouseSignal>>().having(
            (fault) => fault.signal,
            'signal',
            HouseSignal.timedOut,
          ),
        ),
      );
      await client.dispose();
    });

    test('attaches the headers the source built', () async {
      late http.Request seen;
      final client = clientAnswering((request) async {
        seen = request;
        return jsonOk({'ok': true});
      }, headers: (request) async => {'x-app-key': 'abc'});

      await client.send(const RestRequest(path: 'brand/7'));

      expect(seen.headers['x-app-key'], 'abc');
      await client.dispose();
    });

    test('lets a request override a header the source built', () async {
      late http.Request seen;
      final client = clientAnswering((request) async {
        seen = request;
        return jsonOk({'ok': true});
      }, headers: (request) async => {'x-app-key': 'abc'});

      await client.send(
        const RestRequest(path: 'brand/7', headers: {'x-app-key': 'override'}),
      );

      expect(seen.headers['x-app-key'], 'override');
      await client.dispose();
    });

    test('sends fields and files as one multipart body', () async {
      late http.Request seen;
      final client = clientAnswering((request) async {
        seen = request;
        return jsonOk({'ok': true});
      });

      await client.send(
        RestRequest(
          path: 'brand',
          method: RestMethod.post,
          fields: const {'name': 'Acme'},
          uploads: [
            RestUpload(
              field: 'logo',
              bytes: Uint8List.fromList([1, 2, 3]),
              filename: 'logo.jpg',
              contentType: 'image/jpeg',
            ),
          ],
        ),
      );

      final payload = String.fromCharCodes(seen.bodyBytes);
      expect(seen.headers['content-type'], contains('multipart/form-data'));
      expect(payload, contains('name="name"'));
      expect(payload, contains('filename="logo.jpg"'));
      expect(payload, contains('image/jpeg'));
      await client.dispose();
    });

    test('refuses a call that duplicates one in flight', () async {
      final blocked = Completer<http.Response>();
      final client = clientAnswering((request) => blocked.future);

      final first = client.send(
        const RestRequest(path: 'brand/7', dedupKey: 'brand/7'),
      );
      await pumpEventQueue();

      await expectLater(
        client.send(const RestRequest(path: 'brand/7', dedupKey: 'brand/7')),
        throwsA(
          isA<Fault<HouseSignal>>().having(
            (fault) => fault.signal,
            'signal',
            HouseSignal.duplicate,
          ),
        ),
      );

      blocked.complete(jsonOk({'ok': true}));
      await first;
      await client.dispose();
    });

    test('performs one call for two sends sharing a key', () async {
      final blocked = Completer<http.Response>();
      var calls = 0;
      final client = clientAnswering((request) {
        calls++;
        return blocked.future;
      });

      final waiting = [
        client.send(const RestRequest(path: 'brand/7', shareKey: 'brand/7')),
        client.send(const RestRequest(path: 'brand/7', shareKey: 'brand/7')),
      ];
      await pumpEventQueue();
      blocked.complete(jsonOk({'data': 'shared'}));

      final answers = await Future.wait(waiting);
      expect(calls, 1);
      expect(answers.first.map['data'], 'shared');
      expect(answers.last.map['data'], 'shared');
      await client.dispose();
    });

    test('gives the shared failure to both senders', () async {
      var calls = 0;
      final client = clientAnswering((request) async {
        calls++;
        return http.Response(
          '{}',
          404,
          headers: {'content-type': 'application/json'},
        );
      });

      final expected = throwsA(
        isA<Fault<HouseSignal>>().having(
          (fault) => fault.signal,
          'signal',
          HouseSignal.notFound,
        ),
      );
      final waiting = [
        expectLater(
          client.send(const RestRequest(path: 'brand/7', shareKey: 'brand/7')),
          expected,
        ),
        expectLater(
          client.send(const RestRequest(path: 'brand/7', shareKey: 'brand/7')),
          expected,
        ),
      ];

      await Future.wait(waiting);
      expect(calls, 1);
      await client.dispose();
    });

    test('keeps a client it was handed open when disposed', () async {
      final shared = MockClient((request) async => jsonOk({'ok': true}));
      final client = RestClient<HouseSignal>(
        baseUrl: houseBase,
        classifier: const HouseClassifier(),
        guard: CallGuard<HouseSignal>(duplicateSignal: HouseSignal.duplicate),
        httpClient: shared,
      );

      await client.dispose();

      expect(
        (await shared.get(Uri.parse('https://house.test/ping'))).statusCode,
        200,
      );
    });
  });
}

class SocketFailure implements Exception {
  const SocketFailure();
}
