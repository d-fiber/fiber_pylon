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

import '../fault/fault.dart';
import 'response.dart';

/// Turns what an HTTP call did into the adapter's own signal.
///
/// This is where one server's conventions stop and the contract begins, and it
/// is the only place in a REST adapter that reads a status code. Everything
/// downstream sees a [Fault] carrying a signal, so swapping one REST backend for
/// another is a matter of writing another classifier, another set of tables, and
/// nothing else.
///
/// Pylon supplies none of it, not even the obvious half. `status >= 400` looks
/// universal until it meets the API that answers `200` with an error payload, or
/// the one where `404` is an ordinary answer meaning the resource is simply not
/// there yet. Both exist, and both are entitled to say so here.
///
/// ```dart
/// class AdminClassifier implements RestClassifier<AdminSignal> {
///   const AdminClassifier();
///
///   @override
///   AdminSignal? ofResponse(RestResponse response) {
///     if (response.status >= 200 && response.status < 300) return null;
///
///     final body = response.body;
///     final code = body is Map<String, dynamic> ? body['code'] : null;
///     if (code == 'vpn_required') return AdminSignal.vpnRequired;
///     if (code == 'name_empty') return AdminSignal.nameEmpty;
///
///     return switch (response.status) {
///       401 => AdminSignal.unauthorized,
///       403 => AdminSignal.forbidden,
///       404 => AdminSignal.notFound,
///       409 => AdminSignal.statusConflict,
///       429 => AdminSignal.tooManyRequests,
///       _ => AdminSignal.unknown,
///     };
///   }
///
///   @override
///   AdminSignal ofTransport(Object error, StackTrace stackTrace) =>
///       error is TimeoutException ? AdminSignal.timedOut : AdminSignal.noRoute;
/// }
/// ```
abstract interface class RestClassifier<S extends Object> {
  /// The signal [response] amounts to, or `null` when it was a success.
  ///
  /// Called for every answer the server gives, whatever its status. Returning
  /// `null` lets the response through to the caller; returning a signal turns it
  /// into a [Fault] carrying that signal, with the decoded body as its details.
  S? ofResponse(RestResponse response);

  /// The signal for a call that never got an answer.
  ///
  /// [error] is whatever the HTTP stack threw: a socket error, a timeout, a
  /// failed DNS lookup, a refused connection. Telling these apart matters more
  /// than it looks, because a credential manager decides between revoking and
  /// retrying on exactly this distinction, and a timeout that gets named like a
  /// rejection signs people out during an outage.
  S ofTransport(Object error, StackTrace stackTrace);
}
