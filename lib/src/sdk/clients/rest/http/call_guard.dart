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

import '../../../../common/fault.dart';
import '../../../../credential/credentials.dart';

/// Wraps a call in the policy that is the same whatever the call is.
///
/// Pylon defines no request type, no response type and no notion of a route,
/// because those belong to whichever backend is plugged in. What it does own is
/// the handful of rules every adapter would otherwise rewrite, and rewrite worse
/// the second time: renew before a call rather than after it has already failed,
/// refuse a call that duplicates one still in flight, and replay a call once
/// after the credential was renewed.
///
/// Two calls that would collide are handled in one of two ways, and they are not
/// interchangeable. [run] with a `dedupKey` **refuses** the second, which is
/// what protects a mutation from being submitted twice. [share] **joins** it to
/// the first and hands both the same answer, which is what turns two screens
/// asking for the same resource into one request. A read wants the second, a
/// creation wants the first, and only the caller knows which it is.
///
/// A call it refuses as a duplicate throws a [Fault] caused by a
/// [DuplicateCall], and one that renews the credential does so on the statuses
/// it is given.
///
/// ```dart
/// final guard = CallGuard.renewing(renewOn: {401});
///
/// Future<Map<String, dynamic>> read(String id) => guard.run(
///   () => _http.get('brand/$id'),
///   dedupKey: 'brand/$id',
/// );
/// ```
class CallGuard {
  final bool _renewing;
  final Set<int> _renewOn;
  final Set<String> _inFlight = <String>{};
  final Map<String, Future<Object?>> _shared = <String, Future<Object?>>{};

  /// Guards calls that carry no credential.
  ///
  /// Only deduplication is left, which is what an adapter with no notion of a
  /// credential needs.
  CallGuard() : _renewing = false, _renewOn = const {};

  /// Guards calls made against the app's `Credentials`, which must have been set
  /// up by `configureSdk`.
  ///
  /// [renewOn] lists the statuses for which it is worth renewing the credential
  /// and trying the call again. It is required and has no default: which status
  /// means a stale credential depends on the backend, and guessing would wire a
  /// renewal onto a refusal that had nothing to do with one.
  ///
  /// The same set decides revocation. When a replayed call fails with a status
  /// that is still in [renewOn], the credential could not be made to work and is
  /// cleared, because every subsequent call would otherwise rediscover that one
  /// at a time.
  CallGuard.renewing({required Set<int> renewOn}) : _renewing = true, _renewOn = renewOn;

  /// Runs [call] under the policy.
  ///
  /// [dedupKey] identifies what would be a duplicate. Two calls sharing a key
  /// cannot be in flight at once: the second throws a [Fault] caused by a
  /// [DuplicateCall], rather than waiting, because
  /// the caller that lost the race wanted a fresh answer and the winner is
  /// already producing one. Leave it `null` for a call that may legitimately
  /// overlap with itself.
  ///
  /// [authenticated] says whether this call carries the credential. When it does
  /// not, neither renewal nor replay applies and only deduplication is left.
  ///
  /// Throws whatever [call] throws, which for an adapter respecting the contract
  /// is always a [Fault].
  Future<T> run<T>(Future<T> Function() call, {String? dedupKey, bool authenticated = true}) async {
    if (dedupKey != null && !_inFlight.add(dedupKey)) {
      throw const Fault(cause: DuplicateCall());
    }

    try {
      return await _execute(call, authenticated: authenticated);
    } finally {
      if (dedupKey != null) _inFlight.remove(dedupKey);
    }
  }

  /// Runs [call], or waits for the one already running under [key].
  ///
  /// The opposite half of [run]'s deduplication: instead of refusing the second
  /// caller, this hands it the answer the first is already waiting for. Six
  /// widgets that mount at once and each ask for the same resource make one
  /// request, and all six get its result, including its failure.
  ///
  /// The saving is not only the request. Under [run] the losers of the race come
  /// back with a refusal they have to render as something, and the usual answer
  /// is to show nothing or to ask again a moment later. Here they come back with
  /// the data.
  ///
  /// [key] identifies the answer, not the call site, so it must cover everything
  /// that changes what comes back: the path, the parameters, and the account it
  /// is read for. Two calls that would not accept each other's answer must not
  /// share a key.
  ///
  /// Only for calls that read. A call that changes something and is asked for
  /// twice was either asked twice on purpose or is a double submission that
  /// [run] exists to refuse, and neither is served by handing back an earlier
  /// answer.
  ///
  /// The key is released as soon as the call settles, so this coalesces what
  /// overlaps in time and caches nothing. A caller arriving afterwards runs a
  /// fresh call.
  ///
  /// Throws whatever [call] throws, to every caller that joined.
  Future<T> share<T>(Future<T> Function() call, {required String key, bool authenticated = true}) {
    final running = _shared[key];
    if (running != null) return running.then((value) => value as T);

    final started = _execute(call, authenticated: authenticated);
    _shared[key] = started;
    started.whenComplete(() => _shared.remove(key)).ignore();
    return started;
  }

  /// Whether a call is in flight under [dedupKey].
  bool isInFlight(String dedupKey) => _inFlight.contains(dedupKey);

  /// Whether a shared call is in flight under [key].
  bool isShared(String key) => _shared.containsKey(key);

  Future<T> _execute<T>(Future<T> Function() call, {required bool authenticated}) async {
    if (authenticated && _renewing) await Credentials.ensureFresh();
    return _attempt(call, authenticated: authenticated);
  }

  Future<T> _attempt<T>(Future<T> Function() call, {required bool authenticated}) async {
    try {
      return await call();
    } on Fault catch (fault) {
      if (!authenticated || !_renewing || !_renewOn.contains(fault.status)) rethrow;

      final before = Credentials.value;
      await Credentials.renew();
      final after = Credentials.value;
      if (after == null || identical(after, before)) rethrow;

      try {
        return await call();
      } on Fault catch (replayed) {
        if (_renewOn.contains(replayed.status)) await Credentials.clear();
        rethrow;
      }
    }
  }
}
