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

import '../rest/request.dart';
import '../rest/response.dart';

/// How a project decides whether a cached answer is still worth trusting,
/// and how fresh a new one is compared to what is already held.
///
/// The direct analogue of `RestClassifier`: pylon has no opinion of its own
/// about what freshness or a version means for one particular server, so a
/// project supplies this once, when it wants caching at all, the same
/// discipline `CredentialManager.fatalSignals` already holds for renewal.
///
/// ```dart
/// class AdminCachePolicy implements CachePolicy {
///   const AdminCachePolicy();
///
///   @override
///   Duration? ttlFor(RestRequest request) =>
///       request.method == RestMethod.get
///           ? const Duration(minutes: 5)
///           : null;
///
///   @override
///   String? versionOf(RestResponse response) => response.headers['etag'];
///
///   @override
///   bool isNewer(String? cached, String? incoming) => incoming != cached;
/// }
/// ```
abstract interface class CachePolicy {
  /// How long an answer to [request] stays worth trusting without asking
  /// again, or `null` when [request] should never be cached.
  Duration? ttlFor(RestRequest request);

  /// The version [response] carries, read however this server attaches one
  /// — an `ETag` header, a body field, a timestamp. `null` when it carries
  /// none.
  String? versionOf(RestResponse response);

  /// Whether [incoming] is newer than [cached].
  ///
  /// Never assumed to sort lexicographically or numerically: a project's own
  /// version scheme decides what "newer" means for it.
  bool isNewer(String? cached, String? incoming);
}
