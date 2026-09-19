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

import 'package:equatable/equatable.dart';

/// A failure crossing from a backend adapter to the contract built on top of it.
///
/// [S] is the adapter's own set of failure signals, usually an enum it declares.
/// Pylon carries it and never interprets it: the adapter decides what its
/// signals are, and the project decides what each one becomes, through a
/// [FaultResolver].
///
/// ```dart
/// enum RestSignal { unauthorized, forbidden, notFound, nameEmpty, unknown }
///
/// throw const Fault(RestSignal.nameEmpty);
/// ```
///
/// An adapter has to name its failures, and name them the same way every time,
/// since the contract keys on them. A REST adapter turns a status and a body
/// into a signal, a Firebase adapter turns a platform exception into one, and
/// the two do not need to agree with each other.
class Fault<S extends Object> extends Equatable implements Exception {
  /// What went wrong, in the adapter's own vocabulary.
  ///
  /// Usually a member of an enum the adapter declares.
  final S signal;

  /// What the backend sent alongside the failure, for the project to read.
  ///
  /// Usually a decoded error body. Its shape is up to the backend.
  final Object? details;

  /// The original exception this fault was built from, when there was one.
  ///
  /// Kept for crash reports and debugging.
  final Object? cause;

  /// The stack trace of [cause], when the adapter captured it.
  final StackTrace? stackTrace;

  /// A fault reporting that [signal] went wrong.
  const Fault(this.signal, {this.details, this.cause, this.stackTrace});

  @override
  String toString() => 'Fault($signal)';

  /// Two faults are equal when they have the same [signal] and [details].
  ///
  /// [cause] and [stackTrace] are debugging context and are ignored.
  @override
  List<Object?> get props => [signal, details];
}

/// Turns a [Fault] into the error type one operation declares.
///
/// The signals of an adapter are its own, while an operation can fail for a
/// closed set of reasons of its own. A resolver is the `switch` that maps one to
/// the other. It is written next to the adapter, so that swapping backends means
/// writing new resolvers and nothing above them changes. Both sides are typed, so
/// a member that is renamed or does not exist fails to compile:
///
/// ```dart
/// final createBrand = FaultResolver<RestSignal, CreateBrandError>(
///   (signal) => switch (signal) {
///     RestSignal.unauthorized => CreateBrandError.unauthorized,
///     RestSignal.forbidden => CreateBrandError.notPermitted,
///     RestSignal.nameEmpty => CreateBrandError.nameEmpty,
///     _ => CreateBrandError.unknown,
///   },
/// );
/// ```
///
/// Nothing is inferred. The resolver runs the `switch` the project wrote and
/// answers whatever its `_` case decided for a signal the `switch` does not
/// name.
class FaultResolver<S extends Object, E> {
  /// Backs [resolve] and [fallback].
  final E Function(S? signal) _resolve;

  /// Declares how a signal becomes this operation's own error.
  ///
  /// The `switch` names the failures the operation distinguishes and ends with a
  /// `_` case for the rest, which covers the failure nobody thought of and the
  /// one an adapter starts sending after a change. It also receives `null` for
  /// [fallback], which only that `_` case matches.
  const FaultResolver(this._resolve);

  /// The error [fault] corresponds to.
  E call(Fault<S> fault) => resolve(fault.signal);

  /// The error [signal] corresponds to.
  E resolve(S signal) => _resolve(signal);

  /// The error every unlisted signal resolves to.
  E get fallback => _resolve(null);
}
