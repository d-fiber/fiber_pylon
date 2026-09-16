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

import '../../barrier/fault.dart';

/// The one thing a backend supplies for pylon to keep a credential alive.
///
/// Everything else about renewal is policy and lives in [CredentialManager]:
/// when to renew, how to collapse two simultaneous attempts into one, when to
/// retry, when to give up and revoke. A backend that had to provide any of that
/// would be reimplementing it, and the second implementation is always the worse
/// one.
///
/// The whole interface is one method on purpose. Plugging a different backend
/// means writing it, and nothing else.
abstract interface class CredentialRefresher<C extends Object> {
  /// Exchanges [current] for a fresh credential.
  ///
  /// Throws a [Fault] naming what went wrong. The manager does not read that
  /// name: it hands it to the `isFatal` predicate it was given, and that answer
  /// decides between revoking the credential and keeping it for another attempt.
  ///
  /// What this obliges an adapter to do is name its failures consistently, and
  /// to distinguish two situations that look alike from the inside: a credential
  /// the backend rejected, and a backend that could not be reached. They are the
  /// two sides the predicate has to tell apart, and an adapter that gives them
  /// the same name makes that impossible. Confusing them is expensive in both
  /// directions: one signs people out during an outage, the other leaves them
  /// retrying a credential that is gone.
  Future<C> refresh(C current);
}
