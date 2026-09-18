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

import 'environments.dart';

/// What an [Sdk] talks to, closed rather than a free-form name, so a project
/// can act on it — showing a network indicator, say — without recognising one
/// server by name.
enum SdkClientKind {
  /// Reaches a server over REST, or a live connection alongside it.
  rest,

  /// Keeps everything on the device, with nothing to reach over the network.
  local,

  /// Reaches an external service through a vendor's own SDK — Firebase,
  /// Supabase, a company's own client — rather than pylon's own [RestClient].
  vendor,
}

/// An implementation that says which [SdkClientKind] it talks to, standing
/// next to [Sdk] rather than under it.
///
/// [Sdk] is the implementation that resolves a project's own [ValkeryStorage];
/// this is the implementation for a backend that manages its own bootstrap,
/// or needs none, and gets [initialize] and [dispose] as they are, with
/// nothing of its own to add before registering.
///
/// A project rarely extends this directly: [RestSdkClient], [LocalSdkClient]
/// and [VendorSdkClient] already fix [client] to the one that matches, so a
/// backend only has to say which of the three it is.
///
/// An implementation's own `initialize` calls `super.initialize()` **last**,
/// once its own setup — opening a client, restoring a credential — has
/// actually succeeded: registering a backend that failed to configure itself
/// would hand every later caller of [instance] a half built one. Its
/// `dispose` calls `super.dispose()` last too, after releasing whatever
/// `initialize` opened.
///
/// Every [SdkClient] is a singleton of its own concrete type without doing
/// anything for it: [initialize] registers `this` the moment it succeeds, and
/// [instance] hands it back from anywhere, keyed by that type rather than by
/// a handle a project would otherwise have to declare and thread through
/// itself.
abstract base class SdkClient {
  static final Map<Type, SdkClient> _instances = {};

  /// The [T] that last reached the end of [initialize].
  ///
  /// A project never declares a registry of its own for this: every
  /// [SdkClient] becomes reachable this way as soon as its own `initialize`
  /// reaches `super.initialize()`, keyed by its concrete type — the same one
  /// [T] must be called with.
  ///
  /// Throws a [StateError] naming [T] when it was never initialized, or was
  /// disposed since.
  static T instance<T extends SdkClient>() {
    final found = _instances[T];
    if (found == null) {
      throw StateError('$T is not initialized. Call $T().initialize() before using it.');
    }
    return found as T;
  }

  /// What this implementation talks to.
  SdkClientKind get client;

  /// What this implementation needs before it can start, or `null` when it
  /// needs nothing. Checked by [initialize] before anything else runs.
  Environments? get environments;

  bool _isInitialized = false;

  /// Whether [initialize] has already run.
  bool get isInitialized => _isInitialized;

  /// Wires this implementation up and makes it usable.
  ///
  /// Does nothing when this instance is already [isInitialized]. Otherwise,
  /// when [environments] is not `null`, throws an [EnvironmentError] naming
  /// everything missing rather than letting an implementation fail later,
  /// deeper, and less clearly — leaving [isInitialized] `false`, so a caller
  /// that fixes the environment and tries again is not turned away by a
  /// registration that never actually succeeded. Otherwise registers `this`
  /// under its own concrete type, so [instance] can hand it back. An override
  /// does whatever else it needs — opening connections, restoring a
  /// credential — starting with `await super.initialize();` last, so nothing
  /// is registered before its own setup has actually succeeded.
  ///
  /// Calling it twice must be harmless, because a host that recovers from a
  /// failed start will call it again.
  @mustCallSuper
  Future<void> initialize() async {
    if (isInitialized) return;

    final envs = environments;
    if (envs != null && !envs.isComplete) {
      throw EnvironmentError(client: client, missing: envs.missing);
    }

    _isInitialized = true;
    _instances[runtimeType] = this;
  }

  /// Releases everything [initialize] took.
  ///
  /// Does nothing when this instance was never [isInitialized]. Otherwise
  /// forgets its registration, so a later call to [instance] fails again
  /// until something new registers, and unregisters `this` from [instance]
  /// unless a newer instance of the same type already replaced it — a
  /// backend swap that never disposed the one it replaced must not cost the
  /// new one its own registration. An override releases whatever else it
  /// opened, and must be safe to call on an implementation that was never
  /// initialised, and safe to call twice, since it runs on paths that are
  /// already going wrong.
  @mustCallSuper
  Future<void> dispose() async {
    if (!isInitialized) return;
    _isInitialized = false;

    if (identical(_instances[runtimeType], this)) {
      _instances.remove(runtimeType);
    }
  }
}
