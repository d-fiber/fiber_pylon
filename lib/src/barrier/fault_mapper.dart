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

import '../toolkit/reporter.dart';
import 'fault.dart';
import 'result.dart';

/// Turns a [Fault] into the error type one operation declares.
///
/// This is the second half of the boundary. A [Fault] carries a failure across
/// it under the adapter's own signal; a mapper turns that signal into the closed
/// set of reasons a given operation is allowed to fail for. The same contract
/// therefore accepts a REST adapter and a Firebase one without either knowing
/// the other exists.
///
/// Both sides of the table are typed, so a member that does not exist does not
/// compile and a rename is caught rather than discovered at runtime:
///
/// ```dart
/// const createBrand = FaultMapper<RestSignal, CreateBrandError>(
///   signals: {
///     RestSignal.unauthorized: CreateBrandError.unauthorized,
///     RestSignal.forbidden: CreateBrandError.notPermitted,
///     RestSignal.vpnRequired: CreateBrandError.vpnRequired,
///     RestSignal.tooManyRequests: CreateBrandError.tooManyRequests,
///     RestSignal.noRoute: CreateBrandError.networkError,
///     RestSignal.nameEmpty: CreateBrandError.nameEmpty,
///     RestSignal.nameTooLong: CreateBrandError.nameTooLong,
///   },
///   fallback: CreateBrandError.unknown,
/// );
/// ```
///
/// **Nothing here is inferred.** The mapper reads neither side's member names,
/// recognises no spelling, and has no opinion about what a failure means. It
/// looks a value up in a table the project wrote and answers [fallback] when the
/// value is not in it.
///
/// A table belongs next to the adapter, not to the contract, because it is the
/// translation of one backend's vocabulary. Swapping backends means writing new
/// tables beside the new adapter; the contract, and everything above it, does
/// not move.
class FaultMapper<S extends Object, E> {
  final Map<S, E> _signals;
  final E _fallback;
  final Reporter _reporter;

  /// Declares which error answers which signal.
  ///
  /// [signals] is partial on purpose: an operation lists the failures it
  /// actually distinguishes and nothing more.
  ///
  /// [fallback] is required, and there is no default. It answers a signal the
  /// table does not list, which covers both the failure nobody thought of and
  /// the one an adapter starts sending after a change. Only the project knows
  /// which of its members means "we do not know".
  ///
  /// [reporter] receives anything thrown that was not a [Fault] of this
  /// adapter's, so a bug in an adapter is visible instead of silently becoming
  /// [fallback].
  const FaultMapper({
    Map<S, E> signals = const {},
    required E fallback,
    Reporter reporter = const SilentReporter(),
  }) : _signals = signals,
       _fallback = fallback,
       _reporter = reporter;

  /// The error [fault] corresponds to.
  E call(Fault<S> fault) => resolve(fault.signal);

  /// The error [signal] corresponds to.
  E resolve(S signal) => _signals[signal] ?? _fallback;

  /// The error every unlisted signal resolves to.
  E get fallback => _fallback;

  /// Runs [operation] and turns anything it throws into a [Failure].
  ///
  /// This is the shape every port method takes, so it lives here rather than
  /// being written once per method.
  ///
  /// A `Fault<S>` goes through the table. Anything else is reported and becomes
  /// [fallback]: a raw exception, or a fault carrying another adapter's signal,
  /// is a bug in the adapter, and it must neither reach the caller as a crash
  /// nor disappear.
  Future<Result<T, E>> guard<T>(Future<T> Function() operation) async {
    try {
      return OK(await operation());
    } on Fault<S> catch (fault) {
      return Failure(call(fault));
    } catch (error, stackTrace) {
      _reporter.recordError(
        error,
        stackTrace,
        context: {'operation': 'guarded call'},
      );
      return Failure(_fallback);
    }
  }
}
