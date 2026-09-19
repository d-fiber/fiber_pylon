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

import '../segment.dart';
import 'client.dart';
import 'request.dart';
import 'response.dart';

/// One address in a REST resource tree, rooted at a [RestClient]'s base URL.
///
/// [path] never talks to the network, it only remembers one more branch. Any
/// node can also carry a verb directly, because a node built by [path] is
/// always a complete address — there is no partly-composed state left to
/// protect against, as long as every parameter it carries has been resolved
/// by [parameters] first.
final class RestNode<S extends Object> {
  /// The root of [client]'s resource tree.
  RestNode(RestClient<S> client) : this._(client, const [], const {}, true);

  RestNode._(this._client, this._segments, this._headers, this._authenticated);

  final RestClient<S> _client;
  final List<_PathPart> _segments;
  final Map<String, String> _headers;
  final bool _authenticated;

  /// The resolved path this node addresses, relative to the client's base
  /// URL.
  ///
  /// Throws a [StateError] while a parameter [path] left unresolved remains,
  /// since that is not an address yet, only the shape of one.
  String get resolvedPath {
    final unresolved = _segments.whereType<_Parameter>();
    if (unresolved.isNotEmpty) {
      throw StateError(
        'unresolved ${unresolved.map((p) => p.name).join(', ')}: call '
        'parameters() first',
      );
    }
    return _segments.cast<_Literal>().map((s) => s.value).join('/');
  }

  /// The branch [build] describes below this one.
  ///
  /// [build] receives an empty [RestPath] and returns the one it composed,
  /// through [RestPath.segment] for text this SDK's own author writes once,
  /// such as `'brand'` or `'v1/store'`, and [RestPath.parameter] for a value
  /// [parameters] resolves later, at the point a caller actually has it:
  ///
  /// ```dart
  /// final review = store.path((p) => p.segment('review').parameter('id'));
  /// ```
  ///
  /// [RestPath.parameter] is the only place an identifier, a search term, or
  /// any value that did not originate in this SDK's own source belongs —
  /// never interpolated into a [RestPath.segment] directly, which would let
  /// it inject extra segments unnoticed.
  RestNode<S> path(RestPath Function(RestPath) build) => RestNode._(
    _client,
    [..._segments, ...build(const RestPath._([]))._parts],
    _headers,
    _authenticated,
  );

  /// Resolves every parameter [path] left behind, replacing each with the
  /// single, opaque, percent-encoded segment [build] supplied for it.
  ///
  /// [build] receives an empty [RestParameters] and returns the one it
  /// composed, through [RestParameters.parameter] once per placeholder:
  ///
  /// ```dart
  /// final review = store.parameters((p) => p.parameter('id', id));
  /// ```
  ///
  /// Throws an [ArgumentError] naming what is missing when a parameter has
  /// nothing supplied for it, and one naming what is unused when [build]
  /// supplies a name no parameter asked for — a call is only ready once the
  /// two match exactly.
  RestNode<S> parameters(RestParameters Function(RestParameters) build) {
    final values = build(const RestParameters._({}))._values;
    final used = <String>{};
    final resolved = _segments.map((part) {
      if (part is! _Parameter) return part;
      final value = values[part.name];
      if (value == null) {
        throw ArgumentError('missing a value for parameter "${part.name}"');
      }
      used.add(part.name);
      return _Literal(opaqueSegment(value));
    }).toList();

    final unused = values.keys.toSet().difference(used);
    if (unused.isNotEmpty) {
      throw ArgumentError(
        'parameters for $unused were given but nothing needs them',
      );
    }
    return RestNode._(_client, resolved, _headers, _authenticated);
  }

  /// Sets headers every call built from this node carries, merged over
  /// whatever the `RestClient` this node's chain is rooted on attaches to
  /// every call.
  ///
  /// Last word wins: a header set here overrides one of the same name the
  /// client would otherwise attach, and a header set further down a chain
  /// overrides one a node higher up already carried. [build] receives
  /// whatever headers this node already carries and returns the one it
  /// composed, through [RestCallHeaders.add] once per header:
  ///
  /// ```dart
  /// final store = api.path((p) => p.segment('store')).headers(
  ///   (h) => h.add('x-app-key', appKey),
  /// );
  /// ```
  RestNode<S> headers(RestCallHeaders Function(RestCallHeaders) build) =>
      RestNode._(
        _client,
        _segments,
        build(RestCallHeaders._(_headers))._values,
        _authenticated,
      );

  /// Marks every call built from this node as not carrying the credential.
  ///
  /// Before every call [get], [post] and the other verbs build, `CallGuard`
  /// would otherwise refresh the credential if it is stale, and retry once
  /// more after renewing it if the server refuses the call for it. Call this
  /// on the one or two nodes that must not go through that: the endpoint
  /// that signs in, and the one the exchange given to `Credentials.renewWith` calls
  /// to renew the credential — that one deadlocks waiting on itself if it is
  /// left authenticated, since renewing is exactly what it is in the middle
  /// of doing.
  ///
  /// ```dart
  /// final refresh = api.path((p) => p.segment('auth/refresh')).unauthenticated();
  /// ```
  RestNode<S> unauthenticated() =>
      RestNode._(_client, _segments, _headers, false);

  /// Reads this resource. See [RestCall] for what it can carry.
  RestCall<S> get() => RestCall._(
    _client,
    resolvedPath,
    RestMethod.get,
    _headers,
    _authenticated,
  );

  /// Reads this resource's headers, without its body. See [RestCall] for
  /// what it can carry.
  RestCall<S> head() => RestCall._(
    _client,
    resolvedPath,
    RestMethod.head,
    _headers,
    _authenticated,
  );

  /// Creates this resource, or submits something that is not a replacement.
  /// See [RestCall] for what it can carry.
  RestCall<S> post() => RestCall._(
    _client,
    resolvedPath,
    RestMethod.post,
    _headers,
    _authenticated,
  );

  /// Replaces this resource whole. See [RestCall] for what it can carry.
  RestCall<S> put() => RestCall._(
    _client,
    resolvedPath,
    RestMethod.put,
    _headers,
    _authenticated,
  );

  /// Changes part of this resource. See [RestCall] for what it can carry.
  RestCall<S> patch() => RestCall._(
    _client,
    resolvedPath,
    RestMethod.patch,
    _headers,
    _authenticated,
  );

  /// Removes this resource. See [RestCall] for what it can carry.
  RestCall<S> delete() => RestCall._(
    _client,
    resolvedPath,
    RestMethod.delete,
    _headers,
    _authenticated,
  );
}

/// One branch of segments composed inside [RestNode.path].
final class RestPath {
  const RestPath._(this._parts);

  final List<_PathPart> _parts;

  /// Appends [literal] to this branch.
  ///
  /// [literal] is text this SDK's own author writes once while wiring a
  /// port, such as `'brand'` or `'v1/store'`. It may carry several segments
  /// separated by `/`, because nothing external ever reaches this parameter.
  RestPath segment(String literal) =>
      RestPath._([..._parts, ...literalSegments(literal).map(_Literal.new)]);

  /// Appends a parameter named [name], resolved later by [RestNode.parameters].
  RestPath parameter(String name) => RestPath._([..._parts, _Parameter(name)]);
}

/// The values [RestNode.parameters] resolves a branch's placeholders with.
final class RestParameters {
  const RestParameters._(this._values);

  final Map<String, Object> _values;

  /// Supplies [value] for the parameter [RestPath.parameter] named [name].
  RestParameters parameter(String name, Object value) =>
      RestParameters._({..._values, name: value});
}

/// One piece of a [RestNode]'s address, either fixed text or a value
/// [RestNode.parameters] has not resolved yet.
sealed class _PathPart {}

/// A piece of text this SDK's own author wrote, through [RestPath.segment].
final class _Literal extends _PathPart {
  _Literal(this.value);

  final String value;
}

/// A placeholder [RestNode.parameters] resolves, named through
/// [RestPath.parameter].
final class _Parameter extends _PathPart {
  _Parameter(this.name);

  final String name;
}

/// A REST call being composed, before it is sent.
///
/// Built only by [RestNode.get], [RestNode.head], [RestNode.post],
/// [RestNode.put], [RestNode.patch] or [RestNode.delete], which is also
/// where it gets the headers [RestNode.headers] set and whether
/// [RestNode.unauthenticated] was called. Every verb accepts every one of
/// [body], [multipart], [queryParameters] and [timeout]: pylon does not
/// guess which combination a server actually needs, and refuses none of
/// them, including a body on a GET or a query parameter on a DELETE.
/// Configure it by cascading whichever it needs, then call [send]:
///
/// ```dart
/// final request = node.get()
///   ..queryParameters((p) => p.parameter('limit', '10'))
///   ..timeout(const Duration(seconds: 5));
/// final response = await request.send();
/// ```
final class RestCall<S extends Object> {
  RestCall._(
    this._client,
    this._path,
    this._method,
    this._headers,
    this._authenticated,
  );

  final RestClient<S> _client;
  final String _path;
  final RestMethod _method;
  final Map<String, String> _headers;
  final bool _authenticated;

  Map<String, dynamic>? _body;
  Map<String, String> _fields = const {};
  List<RestUpload> _files = const [];
  Map<String, String> _queryParameters = const {};
  Duration? _timeout;

  /// Sets the JSON body. Ignored once [multipart] carries a field or a file,
  /// since a call cannot be both.
  ///
  /// [build] receives whatever fields this call already carries and returns
  /// the one it composed, through [RestBody.value] once per field. Last word
  /// wins, so calling this more than once merges rather than starts over:
  ///
  /// ```dart
  /// call.body((b) => b.value('title', title).value('draft', true));
  /// ```
  void body(RestBody Function(RestBody) build) =>
      _body = build(RestBody._(_body ?? const {}))._values;

  /// Sets the plain text fields and files sent as one multipart body,
  /// instead of [body], because a server that accepts a file upload usually
  /// wants a few short values next to it, such as a caption, without asking
  /// for a second call.
  ///
  /// [build] receives whatever fields and files this call already carries
  /// and returns the one it composed, through [RestMultipart.field] once per
  /// field and [RestMultipart.file] once per file. Fields merge last word
  /// wins, and files accumulate, so calling this more than once adds to what
  /// is already there rather than starting over:
  ///
  /// ```dart
  /// call.multipart((m) => m.field('caption', caption).file(upload));
  /// ```
  void multipart(RestMultipart Function(RestMultipart) build) {
    final composed = build(RestMultipart._(_fields, _files));
    _fields = composed._fields;
    _files = composed._files;
  }

  /// Sets the query parameters, merged over anything already in the path.
  ///
  /// [build] receives whatever parameters this call already carries and
  /// returns the one it composed, through [RestQueryParameters.parameter]
  /// once per parameter. Last word wins, so calling this more than once
  /// merges rather than starts over.
  void queryParameters(
    RestQueryParameters Function(RestQueryParameters) build,
  ) =>
      _queryParameters = build(RestQueryParameters._(_queryParameters))._values;

  /// Sets how long to wait for an answer.
  void timeout(Duration value) => _timeout = value;

  /// Sends this call.
  ///
  /// A read (built by [RestNode.get] or [RestNode.head]) joins
  /// whatever is already configured the same way and still in flight, and
  /// answers it the same response, however many are sent. Every other verb
  /// refuses a second call configured the same way while this one is in
  /// flight, rather than sending it. Either way, what makes two calls "the
  /// same" is the path, the sorted [queryParameters], the sorted headers and
  /// the [RestNode.unauthenticated] status the node this call was built from
  /// carries, [body] and [multipart] together — two otherwise identical
  /// calls asking for a different `Accept-Language` are not the same call.
  Future<RestResponse> send() {
    final key = _key(
      _path,
      _method,
      _queryParameters,
      _headers,
      _fields,
      _files,
      _body,
      _authenticated,
    );
    final shares = _method == RestMethod.get || _method == RestMethod.head;
    return _client.send(
      RestRequest(
        path: _path,
        method: _method,
        body: _body,
        fields: _fields,
        files: _files,
        queryParameters: _queryParameters,
        headers: _headers,
        authenticated: _authenticated,
        shareKey: shares ? key : null,
        dedupKey: shares ? null : key,
        timeout: _timeout,
      ),
    );
  }
}

/// The fields [RestCall.body] sends as JSON.
final class RestBody {
  const RestBody._(this._values);

  final Map<String, dynamic> _values;

  /// Supplies [value] for the JSON field named [key].
  RestBody value(String key, Object? value) =>
      RestBody._({..._values, key: value});
}

/// The plain text fields and files [RestCall.multipart] sends as one
/// multipart body.
final class RestMultipart {
  const RestMultipart._(this._fields, this._files);

  final Map<String, String> _fields;
  final List<RestUpload> _files;

  /// Supplies [value] for the field named [key].
  RestMultipart field(String key, String value) =>
      RestMultipart._({..._fields, key: value}, _files);

  /// Adds [upload] to the files this call sends.
  RestMultipart file(RestUpload upload) =>
      RestMultipart._(_fields, [..._files, upload]);
}

/// The query parameters [RestCall.queryParameters] sends.
final class RestQueryParameters {
  const RestQueryParameters._(this._values);

  final Map<String, String> _values;

  /// Supplies [value] for the query parameter named [name].
  RestQueryParameters parameter(String name, String value) =>
      RestQueryParameters._({..._values, name: value});
}

/// The headers [RestNode.headers] sets.
final class RestCallHeaders {
  const RestCallHeaders._(this._values);

  final Map<String, String> _values;

  /// Supplies [value] for the header named [name].
  RestCallHeaders add(String name, String value) =>
      RestCallHeaders._({..._values, name: value});
}

String _key(
  String path,
  RestMethod method,
  Map<String, String> queryParameters,
  Map<String, String> headers,
  Map<String, String> fields,
  List<RestUpload> files,
  Map<String, dynamic>? body,
  bool authenticated,
) {
  final encodedBody = body == null ? '' : jsonEncode(_canonical(body));
  final encodedFields = _sortedQueryParameters(fields);
  final encodedHeaders = _sortedQueryParameters(headers);
  final encodedFiles = files
      .map(
        (file) =>
            '${file.field}:${file.filename}:${file.contentType}:'
            '${file.bytes.length}:${Object.hashAll(file.bytes)}',
      )
      .join('&');
  return '${method.name.toUpperCase()} $authenticated $path'
      '?${_sortedQueryParameters(queryParameters)}'
      '#$encodedBody|$encodedFields|$encodedFiles|$encodedHeaders';
}

String _sortedQueryParameters(Map<String, String> queryParameters) {
  final keys = queryParameters.keys.toList()..sort();
  return keys.map((key) => '$key=${queryParameters[key]}').join('&');
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
