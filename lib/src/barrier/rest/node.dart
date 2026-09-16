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

import '../../toolkit/rest/client.dart';
import '../../toolkit/rest/request.dart';
import '../../toolkit/rest/response.dart';
import '../fault_mapper.dart';
import '../result.dart';
import '../segment.dart';
import 'call_key.dart';

/// One segment of a REST resource tree, rooted at a [RestClient]'s base URL.
///
/// Composing never talks to the network: [node] and [value] only remember one
/// more segment, and neither closes the chain. Only [url] does, into a
/// [RestEndpoint], the sole place a verb can be sent from — an address that is
/// still being composed can therefore never be sent as one by mistake.
final class RestNode<S extends Object> {
  RestNode._(this._client, this._segments);

  final RestClient<S> _client;
  final List<String> _segments;

  /// The root of [client]'s resource tree.
  factory RestNode.root(RestClient<S> client) => RestNode._(client, const []);

  /// The branch [literal] below this one.
  ///
  /// [literal] is text this SDK's author writes once while wiring a port,
  /// such as `'brand'` or `'v1/store'`. It may carry several segments
  /// separated by `/`, because nothing external ever reaches this parameter —
  /// a value that came from a caller, a deep link, or the server belongs in
  /// [value], never here.
  RestNode<S> node(String literal) =>
      RestNode._(_client, [..._segments, ...literalSegments(literal)]);

  /// The branch below this one, at the single, opaque segment [value]
  /// becomes.
  ///
  /// Unlike [node], [value] is never split on `/`: whatever it contains
  /// becomes exactly one percent-encoded path segment. This is the only place
  /// an identifier, a search term, or any value that did not originate in
  /// this SDK's own source belongs. Does not close the chain: a value can be
  /// followed by more [node], more [value], or [url].
  RestNode<S> value(Object value) =>
      RestNode._(_client, [..._segments, opaqueSegment(value)]);

  /// Closes this branch into the endpoint at [literal], relative to it.
  ///
  /// [literal] follows the same rule as [node]'s argument, and defaults to
  /// empty to call this branch's own resource.
  RestEndpoint<S> url([String literal = '']) => RestEndpoint._(
    _client,
    [..._segments, ...literalSegments(literal)].join('/'),
  );
}

/// A concrete address in a REST resource tree, ready to carry a verb.
///
/// Built only by [RestNode.url]. Every verb takes a [FaultMapper] and a
/// [decode], and answers a [Result] directly, rather than the raw
/// [RestResponse] each port would otherwise have to unwrap through its own
/// copy of [FaultMapper.guard].
final class RestEndpoint<S extends Object> {
  RestEndpoint._(this._client, this._path);

  final RestClient<S> _client;
  final String _path;

  /// The resolved path this endpoint calls, relative to the client's base
  /// URL, for a caller that needs to name its own key rather than rely on the
  /// one [CallKey.derived] computes.
  String get path => _path;

  /// Reads this resource, decoded by [decode] and mapped through [mapper].
  ///
  /// [key] defaults to [CallKey.derived], which coalesces two calls that
  /// resolve to the same path, the same (sorted) [query] and the same
  /// [authenticated] flag into one network call answering the same [Result].
  /// A call whose real semantics differ from a plain read passes [key]
  /// explicitly.
  Future<Result<T, E>> get<T, E extends Object>({
    required FaultMapper<S, E> mapper,
    required T Function(RestResponse response) decode,
    Map<String, String> query = const {},
    bool authenticated = true,
    CallKey key = const CallKey.derived(),
    Duration? timeout,
  }) => mapper.guard(() async {
    final resolved = key.resolve(
      deriveShare: () => _readShareKey(query, authenticated),
      deriveDedup: () => null,
    );
    final response = await _client.send(
      RestRequest(
        path: _path,
        query: query,
        authenticated: authenticated,
        shareKey: resolved.shareKey,
        dedupKey: resolved.dedupKey,
        timeout: timeout,
      ),
    );
    return decode(response);
  });

  /// Creates this resource, or submits something that is not a replacement.
  ///
  /// [key] defaults to [CallKey.derived], which refuses a second call sharing
  /// the same path, [query], [authenticated] flag and, for a plain JSON
  /// [body] (neither [fields] nor [uploads]), the same body, while this one
  /// is in flight. A multipart call never derives a key: it requires an
  /// explicit [key] to be protected at all.
  Future<Result<T, E>> post<T, E extends Object>({
    required FaultMapper<S, E> mapper,
    required T Function(RestResponse response) decode,
    Object? body,
    Map<String, String> fields = const {},
    List<RestUpload> uploads = const [],
    Map<String, String> query = const {},
    bool authenticated = true,
    CallKey key = const CallKey.derived(),
    Duration? timeout,
  }) => _mutate(
    RestMethod.post,
    mapper: mapper,
    decode: decode,
    body: body,
    fields: fields,
    uploads: uploads,
    query: query,
    authenticated: authenticated,
    key: key,
    timeout: timeout,
  );

  /// Replaces this resource whole. See [post] for the shared parameters.
  Future<Result<T, E>> put<T, E extends Object>({
    required FaultMapper<S, E> mapper,
    required T Function(RestResponse response) decode,
    Object? body,
    Map<String, String> fields = const {},
    List<RestUpload> uploads = const [],
    Map<String, String> query = const {},
    bool authenticated = true,
    CallKey key = const CallKey.derived(),
    Duration? timeout,
  }) => _mutate(
    RestMethod.put,
    mapper: mapper,
    decode: decode,
    body: body,
    fields: fields,
    uploads: uploads,
    query: query,
    authenticated: authenticated,
    key: key,
    timeout: timeout,
  );

  /// Changes part of this resource. See [post] for the shared parameters.
  Future<Result<T, E>> patch<T, E extends Object>({
    required FaultMapper<S, E> mapper,
    required T Function(RestResponse response) decode,
    Object? body,
    Map<String, String> fields = const {},
    List<RestUpload> uploads = const [],
    Map<String, String> query = const {},
    bool authenticated = true,
    CallKey key = const CallKey.derived(),
    Duration? timeout,
  }) => _mutate(
    RestMethod.patch,
    mapper: mapper,
    decode: decode,
    body: body,
    fields: fields,
    uploads: uploads,
    query: query,
    authenticated: authenticated,
    key: key,
    timeout: timeout,
  );

  /// Removes this resource. See [post] for the shared parameters.
  Future<Result<T, E>> delete<T, E extends Object>({
    required FaultMapper<S, E> mapper,
    required T Function(RestResponse response) decode,
    Map<String, String> query = const {},
    bool authenticated = true,
    CallKey key = const CallKey.derived(),
    Duration? timeout,
  }) => _mutate(
    RestMethod.delete,
    mapper: mapper,
    decode: decode,
    query: query,
    authenticated: authenticated,
    key: key,
    timeout: timeout,
  );

  Future<Result<T, E>> _mutate<T, E extends Object>(
    RestMethod method, {
    required FaultMapper<S, E> mapper,
    required T Function(RestResponse response) decode,
    Object? body,
    Map<String, String> fields = const {},
    List<RestUpload> uploads = const [],
    required Map<String, String> query,
    required bool authenticated,
    required CallKey key,
    required Duration? timeout,
  }) => mapper.guard(() async {
    final resolved = key.resolve(
      deriveShare: () => null,
      deriveDedup: () => _mutationDedupKey(
        method,
        query,
        fields,
        uploads,
        body,
        authenticated,
      ),
    );
    final response = await _client.send(
      RestRequest(
        path: _path,
        method: method,
        body: body,
        fields: fields,
        uploads: uploads,
        query: query,
        authenticated: authenticated,
        shareKey: resolved.shareKey,
        dedupKey: resolved.dedupKey,
        timeout: timeout,
      ),
    );
    return decode(response);
  });

  String _readShareKey(Map<String, String> query, bool authenticated) =>
      'GET $authenticated $_path?${_sortedQuery(query)}';

  String? _mutationDedupKey(
    RestMethod method,
    Map<String, String> query,
    Map<String, String> fields,
    List<RestUpload> uploads,
    Object? body,
    bool authenticated,
  ) {
    if (fields.isNotEmpty || uploads.isNotEmpty) return null;
    final encodedBody = body == null ? '' : jsonEncode(_canonical(body));
    return '${method.name.toUpperCase()} $authenticated $_path'
        '?${_sortedQuery(query)}#$encodedBody';
  }

  String _sortedQuery(Map<String, String> query) {
    final keys = query.keys.toList()..sort();
    return keys.map((key) => '$key=${query[key]}').join('&');
  }

  /// [body] in a form where two logically equal payloads always encode to the
  /// same string, regardless of the order their fields were built in.
  Object? _canonical(Object? body) => switch (body) {
    Map<dynamic, dynamic> map => Map.fromEntries(
      (map.entries.toList()..sort((a, b) => '${a.key}'.compareTo('${b.key}')))
          .map((entry) => MapEntry('${entry.key}', _canonical(entry.value))),
    ),
    List<dynamic> list => list.map(_canonical).toList(),
    _ => body,
  };
}
