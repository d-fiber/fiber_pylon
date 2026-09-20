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

import 'package:equatable/equatable.dart';

/// What the server answered.
///
/// Carries the status, the headers and the body, and interprets none of them.
/// Whether a given status is a success is for `RestClient` to say, not this:
/// it throws a [Fault] for anything outside `200` to `299`.
///
/// The body is not unwrapped either. An envelope like `{"data": ...}` belongs to
/// one server's conventions, so an adapter reads `response.map['data']` itself
/// rather than pylon deciding that every server has an envelope.
class RestResponse extends Equatable {
  /// The HTTP status the server answered with.
  final int status;

  /// The response headers, with lowercased names as `package:http` returns them.
  final Map<String, String> headers;

  /// The body exactly as it arrived.
  ///
  /// Always present, including for a response that was not JSON, so a call that
  /// downloads something has its payload.
  final Uint8List bytes;

  /// The body decoded as JSON, or `null` when it was not JSON.
  ///
  /// Null covers three cases that need no telling apart here: an empty body, a
  /// content type that was not JSON, and JSON that did not parse. In all three
  /// the status is what remains to classify on, and [bytes] still holds whatever
  /// arrived.
  final Object? body;

  /// Describes an answer of [status].
  const RestResponse({
    required this.status,
    required this.headers,
    required this.bytes,
    required this.body,
  });

  /// The decoded body as a JSON object.
  ///
  /// Throws a [TypeError] when the body was something else, which a port turns
  /// into its fallback error and reports. That is the wanted outcome: a server answering a shape nobody expected is a fact
  /// worth seeing, not one to paper over.
  Map<String, dynamic> get map => body as Map<String, dynamic>;

  /// The decoded body as a JSON array.
  ///
  /// Throws a [TypeError] when the body was something else, as [map] does.
  List<Object?> get list => body as List<Object?>;

  @override
  String toString() => 'RestResponse($status)';

  @override
  List<Object?> get props => [status, headers, bytes, body];
}
