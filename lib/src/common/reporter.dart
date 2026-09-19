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

/// The place pylon sends its log messages and its unexpected errors to.
///
/// Pylon does not know what the host app reports to. An app on Crashlytics
/// implements this over Crashlytics, an app on Sentry over Sentry, and a test
/// over a list it later asserts on.
///
/// Implementations must never throw. They are called from `finally` blocks and
/// from timer callbacks, where a failure would replace the real error with a
/// meaningless one.
abstract interface class Reporter {
  /// Records that [message] happened, as context for a later error.
  void log(String message);

  /// Records [error] as something that should not have happened.
  ///
  /// [stackTrace] is the stack of [error], when there is one. [fatal] tells the
  /// host whether the app can carry on, and [context] carries the few values that
  /// make the report actionable, such as the operation being performed.
  void recordError(Object error, StackTrace? stackTrace, {bool fatal = false, Map<String, Object?> context = const {}});

  /// Attaches [identifier] to the reports that follow, or detaches it when
  /// `null`.
  void identify(String? identifier);
}

/// A [Reporter] that drops everything.
///
/// It is the default wherever pylon takes a reporter, so the rest works without
/// any reporting being set up.
class SilentReporter implements Reporter {
  /// Creates a reporter that drops everything.
  const SilentReporter();

  @override
  void log(String message) {}

  @override
  void recordError(
    Object error,
    StackTrace? stackTrace, {
    bool fatal = false,
    Map<String, Object?> context = const {},
  }) {}

  @override
  void identify(String? identifier) {}
}
