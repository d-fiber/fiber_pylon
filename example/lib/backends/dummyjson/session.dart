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

/// The credential DummyJSON hands out.
///
/// This type is the adapter's, not pylon's. Pylon is told where the expiry lives
/// and nothing else about it.
class DummySession extends Equatable {
  /// The token every authenticated call carries.
  final String accessToken;

  /// The token exchanged for a fresh pair.
  final String refreshToken;

  /// When [accessToken] stops being accepted.
  final DateTime expiresAt;

  /// Describes a session expiring at [expiresAt].
  const DummySession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  /// Reads a session out of what the server answered.
  ///
  /// The server states a lifetime rather than an instant, so this anchors it
  /// now. [lifetime] is what was asked for when signing in.
  factory DummySession.fromJson(
    Map<String, dynamic> json, {
    required Duration lifetime,
  }) => DummySession(
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String,
    expiresAt: DateTime.now().add(lifetime),
  );

  @override
  List<Object?> get props => [accessToken, refreshToken, expiresAt];
}
