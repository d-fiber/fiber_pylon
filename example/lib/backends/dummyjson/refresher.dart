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

import 'package:fiber_pylon/fiber_pylon.dart';

import 'session.dart';
import 'signals.dart';

/// The one method a backend writes to keep a credential alive.
///
/// Everything around it, when to renew, how to collapse two attempts into one,
/// when to retry and when to give up, is [CredentialManager] and is not written
/// again here.
class DummyRefresher implements CredentialRefresher<DummySession> {
  final RestClient<DummySignal> _client;
  final Duration _lifetime;

  /// Renews through [client], asking for tokens that last [lifetime].
  const DummyRefresher(this._client, this._lifetime);

  @override
  Future<DummySession> refresh(DummySession current) async {
    final response = await _client.send(
      RestRequest(
        path: 'auth/refresh',
        method: RestMethod.post,
        authenticated: false,
        body: {
          'refreshToken': current.refreshToken,
          'expiresInMins': _lifetime.inMinutes,
        },
      ),
    );

    return DummySession.fromJson(response.map, lifetime: _lifetime);
  }
}
