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

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../../../common/fault.dart';
import '../../../../common/reporter.dart';
import '../../../../common/unauthenticated_scope.dart';
import 'call_guard.dart';
import 'classifier.dart';
import 'request.dart';
import 'response.dart';

/// Builds the headers every call carries.
///
/// Called once per request, so it can read a credential that has just been
/// renewed, sign a payload, or stamp a request identifier. Whatever it returns
/// is merged under [RestRequest.headers], which therefore always wins.
///
/// Nothing about authentication is assumed here: an adapter that sends
/// `Authorization: Bearer` writes that, one that sends an API key header writes
/// that instead.
typedef RestHeaders = Future<Map<String, String>> Function(RestRequest request);

/// Talks to one REST API.
///
/// This is the whole of what makes a backend a REST backend: a base URL, a way
/// to name failures, and the headers to carry. Swapping to another REST API
/// means building another one of these, with another base URL and another
/// classifier, and changing nothing above it.
///
/// What it does not do is decide anything. It does not know which statuses are
/// failures, what an error body looks like, how a call is authenticated, or
/// which failures deserve a renewal. Each of those is asked for: the
/// [RestClassifier], the [RestHeaders], and the [CallGuard] the project built.
///
/// ```dart
/// final client = RestClient<AdminSignal>(
///   baseUrl: Uri.parse('https://admin.example.test/v1/admin/'),
///   classifier: const AdminClassifier(),
///   guard: guard,
///   headers: (request) async => {
///     if (Credentials.value case final credential?)
///       'authorization': 'Bearer ${credential.token}',
///     'x-app-key': appKey,
///   },
/// );
///
/// final response = await client.send(
///   RestRequest(path: 'brand/$id', dedupKey: 'brand/$id'),
/// );
/// ```
class RestClient<S extends Object> {
  final Uri _baseUrl;
  final RestClassifier<S> _classifier;
  final CallGuard<S> _guard;
  final RestHeaders? _headers;
  final http.Client _http;
  final bool _ownsHttp;
  final Duration _timeout;
  final Reporter _reporter;

  bool _disposed = false;

  /// Talks to the API rooted at [baseUrl].
  ///
  /// [baseUrl] may carry a path, and it is kept: everything a request asks for
  /// is appended to it, so a base of `https://host/v1/admin/` and a path of
  /// `brand/7` reach `https://host/v1/admin/brand/7`.
  ///
  /// [classifier] names failures, [guard] carries the deduplication and renewal
  /// policy, and [headers] builds what every call carries.
  ///
  /// [httpClient] is there so a test can answer without a network, and so an app
  /// that already has a configured client can share it. One passed in is not
  /// closed by [dispose], because whoever created it owns it.
  ///
  /// [timeout] applies to any request that does not carry its own.
  RestClient({
    required Uri baseUrl,
    required RestClassifier<S> classifier,
    required CallGuard<S> guard,
    RestHeaders? headers,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 30),
    Reporter reporter = const SilentReporter(),
  }) : _baseUrl = baseUrl,
       _classifier = classifier,
       _guard = guard,
       _headers = headers,
       _http = httpClient ?? http.Client(),
       _ownsHttp = httpClient == null,
       _timeout = timeout,
       _reporter = reporter;

  /// Where this client is rooted.
  Uri get baseUrl => _baseUrl;

  /// Performs [request] and answers what the server said.
  ///
  /// Throws a [Fault] carrying the signal the classifier gave, for a response it
  /// called a failure and for a call that never reached the server. It throws
  /// nothing else, which is what lets a port wrap this in a single
  /// `FaultResolver.guard`.
  ///
  /// A request carrying a [RestRequest.shareKey] joins whatever is already in
  /// flight under that key instead of going out again, and one carrying a
  /// [RestRequest.dedupKey] refuses to.
  Future<RestResponse> send(RestRequest request) {
    final shareKey = request.shareKey;
    final authenticated = !isUnauthenticated;
    if (shareKey != null) {
      return _guard.share(() => _perform(request), key: shareKey, authenticated: authenticated);
    }

    return _guard.run(() => _perform(request), dedupKey: request.dedupKey, authenticated: authenticated);
  }

  /// Closes the underlying HTTP client, when this created it.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_ownsHttp) _http.close();
  }

  Future<RestResponse> _perform(RestRequest request) async {
    _reporter.log(request.label);

    final RestResponse response;
    try {
      response = request.isMultipart ? await _sendMultipart(request) : await _sendPlain(request);
    } catch (error, stackTrace) {
      throw Fault<S>(_classifier.ofTransport(error, stackTrace), cause: error, stackTrace: stackTrace);
    }

    final signal = _classifier.ofResponse(response);
    if (signal != null) throw Fault<S>(signal, details: response.body);
    return response;
  }

  Future<RestResponse> _sendPlain(RestRequest request) async {
    final body = request.body;
    final encoded = body == null ? null : jsonEncode(body);

    final message = http.Request(request.method.name.toUpperCase(), _resolve(request));
    message.headers.addAll({
      'accept': 'application/json',
      if (encoded != null) 'content-type': 'application/json; charset=utf-8',
      ...await _headersFor(request),
    });
    if (encoded != null) message.bodyBytes = utf8.encode(encoded);

    return _decode(await _dispatch(message, request));
  }

  Future<RestResponse> _sendMultipart(RestRequest request) async {
    final message = http.MultipartRequest(request.method.name.toUpperCase(), _resolve(request));
    message.headers.addAll({'accept': 'application/json', ...await _headersFor(request)});
    message.fields.addAll(request.fields);
    for (final upload in request.files) {
      message.files.add(
        http.MultipartFile.fromBytes(
          upload.field,
          upload.bytes,
          filename: upload.filename,
          contentType: MediaType.parse(upload.contentType),
        ),
      );
    }

    return _decode(await _dispatch(message, request));
  }

  Future<http.Response> _dispatch(http.BaseRequest message, RestRequest request) async {
    final streamed = await _http.send(message).timeout(request.timeout ?? _timeout);
    return http.Response.fromStream(streamed);
  }

  Future<Map<String, String>> _headersFor(RestRequest request) async {
    final source = _headers;
    return {if (source != null) ...await source(request), ...request.headers};
  }

  Uri _resolve(RestRequest request) {
    final asked = Uri.parse(request.path);
    final segments = <String>[
      ..._baseUrl.pathSegments.where((segment) => segment.isNotEmpty),
      ...asked.pathSegments.where((segment) => segment.isNotEmpty),
    ];
    final queryParameters = <String, String>{...asked.queryParameters, ...request.queryParameters};

    return _baseUrl.replace(pathSegments: segments, queryParameters: queryParameters.isEmpty ? null : queryParameters);
  }

  RestResponse _decode(http.Response response) {
    final contentType = response.headers['content-type'] ?? '';
    Object? body;

    if (contentType.contains('json') && response.bodyBytes.isNotEmpty) {
      try {
        body = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        body = null;
      }
    }

    return RestResponse(status: response.statusCode, headers: response.headers, bytes: response.bodyBytes, body: body);
  }
}
