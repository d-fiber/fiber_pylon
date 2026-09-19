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

/// Either a successful value ([OK]) or a typed error ([Failure]).
///
/// [T] is the success payload and [E] the error, typically an enum the project
/// declares itself. A port returns this instead of throwing, so a caller cannot
/// forget that an operation can fail:
///
/// ```dart
/// switch (await sdk.brand.read(brandId: id)) {
///   case OK(:final data):
///     // use data
///   case Failure(:final error):
///     // handle error
/// }
/// ```
sealed class Result<T, E> {
  const Result();

  /// Whether this result carries a value.
  bool get isOk => this is OK<T, E>;

  /// Whether this result carries an error.
  bool get isFailure => this is Failure<T, E>;

  /// The value when this result succeeded, `null` otherwise.
  ///
  /// A success whose payload is itself `null` is indistinguishable from a
  /// failure here, so prefer pattern matching when `T` is nullable.
  T? get dataOrNull => switch (this) {
    OK<T, E>(:final data) => data,
    Failure<T, E>() => null,
  };

  /// The error when this result failed, `null` otherwise.
  E? get errorOrNull => switch (this) {
    OK<T, E>() => null,
    Failure<T, E>(:final error) => error,
  };

  /// The value when this result succeeded, [fallback] otherwise.
  T orElse(T fallback) => switch (this) {
    OK<T, E>(:final data) => data,
    Failure<T, E>() => fallback,
  };

  /// The result of [ok] on the value, or of [failure] on the error.
  R fold<R>({required R Function(T data) ok, required R Function(E error) failure}) => switch (this) {
    OK<T, E>(:final data) => ok(data),
    Failure<T, E>(:final error) => failure(error),
  };

  /// This result with its value replaced by [transform] of it, a failure staying
  /// as it is.
  Result<R, E> map<R>(R Function(T data) transform) => switch (this) {
    OK<T, E>(:final data) => OK<R, E>(transform(data)),
    Failure<T, E>(:final error) => Failure<R, E>(error),
  };

  /// This result with its error replaced by [transform] of it, a success staying
  /// as it is.
  ///
  /// It is how a service layer converts the errors of the SDK into its own
  /// vocabulary without unwrapping the result.
  Result<T, F> mapError<F>(F Function(E error) transform) => switch (this) {
    OK<T, E>(:final data) => OK<T, F>(data),
    Failure<T, E>(:final error) => Failure<T, F>(transform(error)),
  };
}

/// The success variant of [Result].
class OK<T, E> extends Result<T, E> with Equatable {
  /// The value the operation produced.
  final T data;

  /// Wraps [data] as a successful result.
  const OK(this.data);

  @override
  String toString() => 'OK($data)';

  @override
  List<Object?> get props => [data];
}

/// The failure variant of [Result].
class Failure<T, E> extends Result<T, E> with Equatable {
  /// The reason the operation failed.
  final E error;

  /// Wraps [error] as a failed result.
  const Failure(this.error);

  @override
  String toString() => 'Failure($error)';

  @override
  List<Object?> get props => [error];
}
