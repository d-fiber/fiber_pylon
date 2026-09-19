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

/// What is happening to an [Repository].
///
/// A closed list, so that a screen can `switch` over it and be told by the
/// compiler about the case it forgot. It holds only what pylon can decide by
/// itself: the life of the refresh, whether a credential was there to make it, and
/// whether the network was. What went wrong beyond that belongs to the project,
/// which names it in its own error type `E` and gets it back in [StatusFailed].
///
/// It is announced rather than kept: an outcome reaches whoever follows the
/// status once, and the status is [StatusIdle] again. [StatusRunning] and
/// [StatusOffline] are the two that last.
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

/// Nothing is happening: what the database holds is loaded and the last outcome
/// has been announced.
///
/// Also what an error that was not a `Fault` leaves behind when it cuts a
/// refresh short.
final class StatusIdle<E> extends Status<E> {
  /// The repository is at rest.
  const StatusIdle();

  @override
  String toString() => 'StatusIdle';
}

/// A refresh is under way, or the repository is loading what the database already
/// holds, which is what it starts as.
///
/// Lasts until what it is doing is done, and only then does the outcome replace
/// it.
final class StatusRunning<E> extends Status<E> {
  /// Something is being done.
  const StatusRunning();

  @override
  String toString() => 'StatusRunning';
}

/// A refresh fetched an answer and stored it, or the repository has loaded what
/// the database holds.
///
/// Announced once, and the status is [StatusIdle] again at once.
final class StatusSucceeded<E> extends Status<E> {
  /// It went through.
  const StatusSucceeded();

  @override
  String toString() => 'StatusSucceeded';
}

/// The last refresh could not reach the network.
///
/// Decided before the request when the repository observes the connection and
/// `Network` or its health monitor says it is out, and after it when the request
/// failed with a signal the project listed as meaning the network is out of
/// reach. What is stored is still what the repository reads.
///
/// A repository that observes the connection stays here until the connection is
/// back, and answers a refresh without a request in the meantime. One that does
/// not cannot know when it returns, so it announces this once, like any other
/// outcome.
final class StatusOffline<E> extends Status<E> {
  /// The network was out of reach.
  const StatusOffline();

  @override
  String toString() => 'StatusOffline';
}

/// A refresh needed a credential and none was held, so no request was made.
///
/// Announced once, and the status is [StatusIdle] again at once.
final class StatusUnauthenticated<E> extends Status<E> {
  /// There was no credential to make the request with.
  const StatusUnauthenticated();

  @override
  String toString() => 'StatusUnauthenticated';
}

/// A refresh failed for a reason the project names.
///
/// Announced once, and the status is [StatusIdle] again at once.
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
