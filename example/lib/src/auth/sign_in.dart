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

import '../../clients/rest/rest.dart';
import '../../clients/rest/signal.dart';

final class Session {
  final String token;

  const Session({required this.token});
}

enum SignInError { invalidCredentials, networkError, unknown }

/// Signing in with an email and a password.
///
/// Made for one attempt: `refresh()` sends it and `status` announces how it
/// went, [StatusSucceeded] once the credential is held. `data` says whether one
/// is.
final class SignIn extends Repository<Session, bool, SignInError, RestSignal> {
  SignIn({required this.email, required this.password});

  final String email;
  final String password;

  @override
  bool get requiresCredential => false;

  @override
  Future<Session> fetch() => RestGroundSdk.I.auth.signIn(email: email, password: password);

  @override
  Future<void> response(Session session) => Credentials.set(Credential(token: session.token));

  @override
  Stream<bool> stream() => Credentials.held.stream;

  @override
  SignInError resolve(Fault<RestSignal> fault) => switch (fault.signal) {
    RestSignal.unauthorized => SignInError.invalidCredentials,
    RestSignal.noRoute => SignInError.networkError,
    _ => SignInError.unknown,
  };
}
