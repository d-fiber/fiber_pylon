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

/// A failure, as it crosses the boundary between a backend and the contract
/// built on top of it.
///
/// `S` is the adapter's own vocabulary of things that can go wrong, and pylon
/// never looks at it. Any list of failure kinds pylon offered would be a guess:
/// that every project has authentication, that a word like `unauthorized` means
/// the credentials should be renewed, that a refusal is one of the handful of
/// cases somebody thought of once. Some project would mean something else by the
/// same word and be quietly wired to the wrong behaviour.
///
/// An adapter therefore declares its own signals, and gets a compiler that
/// checks them:
///
/// ```dart
/// enum RestSignal {
///   unauthorized,
///   forbidden,
///   vpnRequired,
///   notFound,
///   tooManyRequests,
///   noRoute,
///   nameEmpty,
///   nameTooLong,
///   unknown,
/// }
///
/// throw const Fault(RestSignal.nameEmpty);
/// ```
///
/// The consequence is worth stating plainly: **naming its failures is an
/// adapter's real job**, and naming them consistently is what makes the contract
/// above able to key on them. A REST adapter turns a status and a body into a
/// signal, a Firebase adapter turns a platform exception into one, and neither
/// has to agree with the other. What has to hold is each adapter against itself.
class Fault<S extends Object> implements Exception {
  /// What went wrong, in the adapter's own vocabulary.
  ///
  /// Usually a member of an enum the adapter declares. Pylon transports it,
  /// compares it against sets the project handed over, and interprets it never.
  final S signal;

  /// Whatever the backend sent alongside the failure, for the project to read.
  ///
  /// Usually a decoded error body. Kept as an [Object] because no shape is
  /// common to two backends, and never looked at here.
  final Object? details;

  /// The original exception this was built from, when there was one.
  ///
  /// Carried for crash reports and debugging. Nothing branches on it.
  final Object? cause;

  /// The stack of [cause], when the adapter captured it.
  final StackTrace? stackTrace;

  /// Reports that [signal] went wrong.
  const Fault(this.signal, {this.details, this.cause, this.stackTrace});

  @override
  String toString() => 'Fault($signal)';
}
