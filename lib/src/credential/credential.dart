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

import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// What a call carries to prove who makes it, and what keeps it alive.
///
/// [token] is the one string a request presents, and pylon reads nothing inside
/// it: a JWT, an opaque key and a session id are all the same here. The other
/// fields say only what renewing it takes, and each is optional so that a
/// credential that never expires, or cannot be exchanged, says so by leaving it
/// out rather than by inventing a value.
///
/// Held and followed through `Credentials`, which is also what keeps it in the
/// operating system's vault.
final class Credential extends Equatable {
  /// A credential presenting [token], asserted to be a string that says something.
  ///
  /// [refreshToken] is what the backend exchanges for a fresh credential, and
  /// without it this one is never renewed. [expiresAt] is when [token] stops
  /// being accepted, and without it nothing is renewed ahead of time. [holder]
  /// names whose credential this is, for `Tenant.follow` to keep each account's
  /// rows apart.
  const Credential({required this.token, this.refreshToken, this.expiresAt, this.holder})
    : assert(token != '', 'a credential presents a token'),
      assert(holder != '', 'a holder is named or left out, never empty');

  /// What a request presents to be let through.
  final String token;

  /// What the backend exchanges for a fresh credential, or `null` when this one
  /// cannot be renewed.
  final String? refreshToken;

  /// When [token] stops being accepted, or `null` when it never does.
  final DateTime? expiresAt;

  /// Whose credential this is, or `null` when it belongs to nobody in
  /// particular. Pylon never reads it except to pick the tenant.
  final String? holder;

  /// The text the vault keeps for this credential.
  @internal
  String encode() => jsonEncode({
    'token': token,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt?.toUtc().toIso8601String(),
    'holder': holder,
  });

  /// The credential [raw] holds, as [encode] wrote it.
  ///
  /// Throws a [FormatException] when [raw] is not one. What it says never
  /// includes [raw], which is a secret and ends up in an error report.
  @internal
  factory Credential.decode(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final expiresAt = json['expiresAt'] as String?;
      return Credential(
        token: json['token'] as String,
        refreshToken: json['refreshToken'] as String?,
        expiresAt: expiresAt == null ? null : DateTime.parse(expiresAt),
        holder: json['holder'] as String?,
      );
    } catch (_) {
      throw const FormatException('the vault holds something that is not a credential');
    }
  }

  /// Describes this credential without ever showing the tokens.
  @override
  String toString() => 'Credential(hidden)';

  /// Compares the instant of [expiresAt] rather than the date object, which a
  /// local time and a UTC time of the same instant do not share.
  @override
  List<Object?> get props => [token, refreshToken, expiresAt?.microsecondsSinceEpoch, holder];
}
