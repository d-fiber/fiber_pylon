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

import 'events_port.dart';
import 'post_port.dart';

/// One implementation of everything this app needs.
///
/// The project declares this, not pylon: pylon supplies the lifetime, through
/// [RestBackendSdk] or [LocalBackendSdk], which every concrete backend
/// extends alongside implementing this; the ports are the project's own.
///
/// Not itself related to [BackendSdk] by `extends` or `implements`, because a
/// concrete class only gets one `extends`, and [RestBackendSdk] or
/// [LocalBackendSdk] already spends it. [initialize] and [dispose] are
/// declared again here so this stays the one type `PostsSdk` needs, and a
/// concrete backend satisfies them for free through whichever of the two it
/// extends.
abstract interface class ExampleBackend {
  /// Wires this backend up. See [Sdk.initialize].
  Future<void> initialize();

  /// Releases everything [initialize] took. See [Sdk.dispose].
  Future<void> dispose();

  /// What this backend talks to, short and stable, for the screen and for
  /// error messages.
  String get name;

  /// A one-line description of what this backend talks to, for the screen.
  String get describe;

  /// Posts, however this backend gets them.
  PostPort get posts;

  /// Live changes to the posts this backend holds, or `null` when this
  /// backend has no way to push them.
  EventsPort? get events;

  /// The credential this backend keeps alive, or `null` when it needs none.
  ///
  /// Read-only here, and typed loosely on purpose: the screen shows whether a
  /// credential is held and how close to expiry it is, and has no business
  /// knowing what one is made of.
  CredentialManager<Object, Object>? get credentials;
}
