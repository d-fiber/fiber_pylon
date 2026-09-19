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

/// Where the last refresh of an [SdkRepository] stands.
///
/// A closed list, so that a screen can `switch` over it and be told by the
/// compiler about the case it forgot. It holds only what pylon can decide by
/// itself: the life of the refresh, whether a credential was there to make it, and
/// whether the network was. What went wrong beyond that belongs to the project,
/// which names it in its own error type `E` and gets it back in [StatusFailed].
///
/// ```dart
/// repository.status.stream.listen((status) => switch (status) {
///   StatusRunning() => showSpinner(),
///   StatusOffline() => showBanner('no network, showing what is stored'),
///   StatusFailed(:final error) => showError(error),
///   _ => hideBanner(),
/// });
/// ```
sealed class Status<E> extends Equatable {
  /// Allows the variants to be const.
  const Status();

  @override
  List<Object?> get props => const [];
}

/// Nothing has been asked yet, or an error that was not a `Fault` cut the last
/// refresh short.
final class StatusIdle<E> extends Status<E> {
  /// The repository is at rest.
  const StatusIdle();

  @override
  String toString() => 'StatusIdle';
}

/// A refresh is under way.
final class StatusRunning<E> extends Status<E> {
  /// A refresh is being made.
  const StatusRunning();

  @override
  String toString() => 'StatusRunning';
}

/// The last refresh fetched an answer and stored it.
///
/// Stays until the next refresh starts.
final class StatusSucceeded<E> extends Status<E> {
  /// The refresh went through.
  const StatusSucceeded();

  @override
  String toString() => 'StatusSucceeded';
}

/// The last refresh could not reach the network.
///
/// Decided by the health monitor the repository was given, or by a signal the project
/// listed as meaning the network is out of reach. What is stored is still what
/// the repository reads.
final class StatusOffline<E> extends Status<E> {
  /// The network was out of reach.
  const StatusOffline();

  @override
  String toString() => 'StatusOffline';
}

/// The last refresh needed a credential and none was held, so no request was
/// made.
final class StatusUnauthenticated<E> extends Status<E> {
  /// There was no credential to make the request with.
  const StatusUnauthenticated();

  @override
  String toString() => 'StatusUnauthenticated';
}

/// The last refresh failed for a reason the project names.
final class StatusFailed<E> extends Status<E> {
  /// The refresh failed with [error], as the project's own resolver turned the
  /// fault into.
  const StatusFailed(this.error);

  /// What went wrong, in the project's own vocabulary.
  final E error;

  @override
  List<Object?> get props => [error];

  @override
  String toString() => 'StatusFailed($error)';
}
