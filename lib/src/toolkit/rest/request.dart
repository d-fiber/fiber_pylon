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

import 'dart:typed_data';

/// The verb of a request.
///
/// The five HTTP defines for a resource API. Unlike the rest of pylon this is a
/// closed list, and it can be: these are a protocol's own words, not a guess
/// about what a project might mean.
enum RestMethod {
  /// Reads a resource without changing anything.
  get,

  /// Creates a resource, or submits something that is not a replacement.
  post,

  /// Replaces a resource whole.
  put,

  /// Changes part of a resource.
  patch,

  /// Removes a resource.
  delete,
}

/// A file travelling in a multipart body.
class RestUpload {
  /// The form field this file is sent under.
  final String field;

  /// The bytes of the file.
  final Uint8List bytes;

  /// The name the server records, which is often ignored but always sent.
  final String filename;

  /// The media type, such as `image/jpeg`.
  ///
  /// Sent verbatim, so a value the server rejects is rejected as written here.
  final String contentType;

  /// Sends [bytes] under [field].
  const RestUpload({
    required this.field,
    required this.bytes,
    required this.filename,
    required this.contentType,
  });
}

/// One call to the API, described without saying how it is performed.
///
/// A request is data. It is built by an adapter, handed to a [RestClient], and
/// nothing about it depends on which server is at the other end: the same
/// request against a different base URL is a different backend answering the
/// same call.
class RestRequest {
  /// The verb.
  final RestMethod method;

  /// Where the resource lives, relative to the client's base URL.
  ///
  /// Leading slashes are ignored, and a query string written here is merged with
  /// [query], so both `brand/$id` and `brand/pagination?offset=0` work.
  final String path;

  /// Query parameters, merged over anything already in [path].
  final Map<String, String> query;

  /// Headers for this call, merged over whatever the client attaches to every
  /// call.
  ///
  /// Last word wins, so a request can override a default the client sets.
  final Map<String, String> headers;

  /// The JSON body, or `null` for a call that sends none.
  ///
  /// Encoded with `jsonEncode`, so anything it accepts works here. Ignored when
  /// [uploads] or [fields] are present, since a call cannot be both.
  final Object? body;

  /// Text fields of a multipart body.
  final Map<String, String> fields;

  /// Files of a multipart body.
  ///
  /// Their presence, or that of [fields], is what makes this a multipart call
  /// rather than a JSON one.
  final List<RestUpload> uploads;

  /// Whether this call carries the credential.
  ///
  /// Passed on to the guard, which is what decides to renew beforehand and to
  /// replay afterwards. A sign-in call, which establishes the credential rather
  /// than using it, sets this to `false`.
  final bool authenticated;

  /// What would make another call a duplicate of this one, or `null` when this
  /// call may overlap with itself.
  ///
  /// Two calls sharing a key cannot be in flight at once: the second is refused.
  /// This is the protection a mutation wants, so that a button pressed twice
  /// creates one thing. A read wants [shareKey] instead.
  final String? dedupKey;

  /// What identifies this call's answer, or `null` to always perform the call.
  ///
  /// A second call arriving under a key already in flight does not go out: it
  /// waits for the first and receives its answer. Six widgets mounting at once
  /// and each asking for the same resource make one request, and all six get its
  /// result.
  ///
  /// The key must cover everything that changes what comes back, since it names
  /// an answer rather than a call site. Only for calls that read, and mutually
  /// exclusive with [dedupKey], because refusing a duplicate and answering it
  /// are opposite decisions.
  final String? shareKey;

  /// How long to wait for an answer, or `null` to use the client's own.
  final Duration? timeout;

  /// Describes a call to [path].
  const RestRequest({
    required this.path,
    this.method = RestMethod.get,
    this.query = const {},
    this.headers = const {},
    this.body,
    this.fields = const {},
    this.uploads = const [],
    this.authenticated = true,
    this.dedupKey,
    this.shareKey,
    this.timeout,
  }) : assert(
         dedupKey == null || shareKey == null,
         'A call either refuses its duplicates or answers them, not both',
       );

  /// Whether this call is sent as a multipart body.
  bool get isMultipart => uploads.isNotEmpty || fields.isNotEmpty;

  /// The verb and path, for a log line or a crash report breadcrumb.
  String get label => '${method.name.toUpperCase()} $path';
}
