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
/// It carries what happened and nothing about what it means: pylon names no
/// failure. An operation turns it into its own error, an enum it declares and
/// completes itself, in the `resolve` it writes.
///
/// ```dart
/// UsersError resolve(Fault fault) => switch (fault.status) {
///   401 || 403 => UsersError.signedOut,
///   null => fault.cause is TimeoutException ? UsersError.timedOut : UsersError.network,
///   _ => UsersError.unknown,
/// };
/// ```
class Fault extends Equatable implements Exception {
  /// The status the server answered, or `null` when it gave no answer.
  final int? status;

  /// What the backend sent alongside the failure, for the operation to read.
  ///
  /// Usually a decoded error body. Its shape is up to the backend.
  final Object? details;

  /// The original exception this fault was built from, when there was one.
  ///
  /// What a call that got no answer failed with: a `TimeoutException` when it
  /// waited too long, a `SocketException` without a network, and a
  /// [DuplicateCall] when an identical call was already in flight.
  final Object? cause;

  /// The stack trace of [cause], when the adapter captured it.
  final StackTrace? stackTrace;

  /// A fault with what an adapter knows of the failure.
  const Fault({this.status, this.details, this.cause, this.stackTrace});

  @override
  String toString() => 'Fault(${status ?? cause.runtimeType})';

  /// Two faults are equal when they have the same [status] and [details] and
  /// were caused by the same type of exception.
  ///
  /// [stackTrace] is debugging context and is ignored.
  @override
  List<Object?> get props => [status, details, cause?.runtimeType];
}

/// What a [Fault] is caused by when an identical call was already in flight and
/// this one was refused.
final class DuplicateCall implements Exception {
  /// A call refused as a duplicate.
  const DuplicateCall();

  @override
  String toString() => 'DuplicateCall';
}
