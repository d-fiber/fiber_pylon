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

/// What happened to the credential held by a [CredentialManager].
enum CredentialEvent {
  /// A credential was found in storage when the manager started.
  ///
  /// Published even when nothing was found, so a caller waiting to know where to
  /// route has one signal to wait for rather than two.
  restored,

  /// A credential was handed to the manager.
  granted,

  /// The credential was exchanged for a fresh one and the previous is now stale.
  renewed,

  /// There is no credential any more, whether the holder asked or the backend
  /// refused to renew.
  revoked,
}

/// One transition of the credential state.
///
/// `C` is whatever the project calls its credential. Pylon never looks inside
/// it.
class CredentialChange<C extends Object> extends Equatable {
  /// What happened.
  final CredentialEvent event;

  /// The credential in force after the transition, `null` after a revocation.
  final C? credential;

  /// Describes the transition [event] leaving [credential] in force.
  const CredentialChange(this.event, this.credential);

  @override
  String toString() => 'CredentialChange(${event.name})';

  @override
  List<Object?> get props => [event, credential];
}
