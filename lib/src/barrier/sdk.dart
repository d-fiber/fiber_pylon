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

import 'package:meta/meta.dart';

import '../toolkit/storage/preferences.dart';

/// The plug.
///
/// An [Sdk] is one implementation of everything a project's contract needs. It
/// declares no operations here, because the operations are the project's and
/// pylon must not know a single one of them: the project writes its own
/// interface listing the ports it has, and requires implementations of it to
/// also extend [Sdk], so they get a lifetime.
///
/// ```dart
/// abstract base class MySdkBackend extends Sdk {
///   BrandPort get brand;
///   StorePort get store;
/// }
/// ```
///
/// That is the whole trick. What crosses the boundary is the project's own
/// interface; what pylon adds is the two moments every implementation has, the
/// one where it wires itself up and the one where it lets go.
abstract base class Sdk {
  /// The project's own local preferences this [initialize] resolves before
  /// anything else, unless one is already resolved. `null` when this
  /// implementation needs none.
  Preferences? get preferences => null;

  /// Wires this implementation up and makes it usable.
  ///
  /// Resolves [preferences], unless [Preferences.isInitialized] already —
  /// once, however many implementations ask for it, and however many times
  /// one of them is initialized again over the app's life. An override does
  /// whatever else it needs — opening connections, restoring a credential,
  /// starting timers — starting with `await super.initialize();`, so the two
  /// never happen in the wrong order.
  ///
  /// Calling it twice must be harmless, because a host that recovers from a
  /// failed start will call it again.
  @mustCallSuper
  Future<void> initialize() async {
    final preferences = this.preferences;
    if (preferences != null && !Preferences.isInitialized) {
      await Preferences.initialize(preferences);
    }
  }

  /// Releases everything [initialize] took.
  ///
  /// Does nothing on its own: [preferences] lives for the app, not for this
  /// one implementation, so nothing here disposes it. An override releases
  /// whatever else it opened, and must be safe to call on an implementation
  /// that was never initialised, and safe to call twice, since it runs on
  /// paths that are already going wrong.
  @mustCallSuper
  Future<void> dispose() async {}
}

/// What an [Sdk] talks to, closed rather than a free-form name, so a project
/// can act on it — showing a network indicator, say — without recognising one
/// server by name.
enum SdkType {
  /// Reaches a server over REST, or a live connection alongside it.
  rest,

  /// Keeps everything on the device, with nothing to reach over the network.
  local,
}

/// An [Sdk] that says which [SdkType] it is.
///
/// A project rarely extends this directly: [RestBackendSdk] and
/// [LocalBackendSdk] already fix [type] to the one that matches, so a backend
/// only has to say which of the two it is.
abstract base class BackendSdk extends Sdk {
  /// What this implementation talks to.
  SdkType get type;
}

/// A [BackendSdk] that reaches a server over REST, or a live connection
/// alongside it.
///
/// A project extends this rather than extending [BackendSdk] directly, so
/// [type] comes for free instead of being redeclared on every REST backend it
/// writes.
abstract base class RestBackendSdk extends BackendSdk {
  @override
  SdkType get type => SdkType.rest;
}

/// A [BackendSdk] that keeps everything on the device, with nothing to reach
/// over the network.
///
/// A project extends this rather than extending [BackendSdk] directly, so
/// [type] comes for free instead of being redeclared on every local backend
/// it writes.
abstract base class LocalBackendSdk extends BackendSdk {
  @override
  SdkType get type => SdkType.local;
}
