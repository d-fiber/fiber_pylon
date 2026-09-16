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

/// The key an HTTP call uses to coalesce or refuse itself against another call
/// already in flight.
///
/// `RestRequest` (in the toolkit) refuses a call that carries both a share key
/// and a deduplication key at once. This type makes that choice explicit
/// rather than leaving a caller free to build a request that would fail that
/// check: [CallKey.derived] resolves to whichever the calling verb uses by
/// default, and [CallKey.share], [CallKey.dedup] and [CallKey.none] each pin
/// down one outcome regardless of the verb — the escape hatch a call whose
/// real semantics differ from its verb needs, such as a paginated read
/// exposed as a `POST` because of a filter body too complex for a query
/// string.
sealed class CallKey {
  const CallKey();

  /// The default for the verb this key is passed to: a share key for a read,
  /// a deduplication key for a mutation.
  const factory CallKey.derived() = _Derived;

  /// Coalesces this call with any other call already in flight under [key].
  const factory CallKey.share(String key) = _Share;

  /// Refuses a second call sharing [key] while this one is in flight.
  const factory CallKey.dedup(String key) = _Dedup;

  /// Associates no key with this call: it may run alongside itself freely.
  const factory CallKey.none() = _None;

  /// Resolves this key into the pair `RestRequest` accepts.
  ///
  /// [deriveShare] and [deriveDedup] are called only for [CallKey.derived],
  /// and only the one the calling verb actually means: a read passes a
  /// [deriveShare] that computes something and a [deriveDedup] that answers
  /// `null`, a mutation the reverse.
  ({String? shareKey, String? dedupKey}) resolve({
    required String? Function() deriveShare,
    required String? Function() deriveDedup,
  });
}

final class _Derived extends CallKey {
  const _Derived();

  @override
  ({String? shareKey, String? dedupKey}) resolve({
    required String? Function() deriveShare,
    required String? Function() deriveDedup,
  }) => (shareKey: deriveShare(), dedupKey: deriveDedup());
}

final class _Share extends CallKey {
  const _Share(this._key);

  final String _key;

  @override
  ({String? shareKey, String? dedupKey}) resolve({
    required String? Function() deriveShare,
    required String? Function() deriveDedup,
  }) => (shareKey: _key, dedupKey: null);
}

final class _Dedup extends CallKey {
  const _Dedup(this._key);

  final String _key;

  @override
  ({String? shareKey, String? dedupKey}) resolve({
    required String? Function() deriveShare,
    required String? Function() deriveDedup,
  }) => (shareKey: null, dedupKey: _key);
}

final class _None extends CallKey {
  const _None();

  @override
  ({String? shareKey, String? dedupKey}) resolve({
    required String? Function() deriveShare,
    required String? Function() deriveDedup,
  }) => (shareKey: null, dedupKey: null);
}
