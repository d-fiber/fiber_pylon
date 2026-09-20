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

import 'clients/rest/http/client.dart';

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
/// interface; what pylon adds is the two moments every implementation has,
/// the one where it wires itself up and the one where it lets go.
///
/// Every [Sdk] is a singleton of its own concrete type without doing anything
/// for it: [initialize] registers `this` the moment it succeeds, and
/// [instance] hands it back from anywhere, keyed by that type rather than by
/// a handle a project would otherwise have to declare and thread through
/// itself.
abstract base class Sdk {
  static final Map<Type, Sdk> _instances = {};

  /// The [T] that last reached the end of [initialize].
  ///
  /// A project never declares a registry of its own for this: every [Sdk]
  /// becomes reachable this way as soon as its own `initialize` reaches
  /// `super.initialize()`, keyed by its concrete type — the same one [T] must
  /// be called with.
  ///
  /// Throws a [StateError] naming [T] when it was never initialized, or was
  /// disposed since.
  static T instance<T extends Sdk>() {
    final found = _instances[T];
    if (found == null) {
      throw StateError('$T is not initialized. Call $T().initialize() before using it.');
    }
    return found as T;
  }

  bool _isInitialized = false;

  /// Whether [initialize] has already run.
  bool get isInitialized => _isInitialized;

  /// Wires this implementation up and makes it usable.
  ///
  /// Does nothing when this instance is already [isInitialized]. Otherwise
  /// marks it so and registers `this` under its own concrete type so
  /// [instance] can hand it back. An override does whatever else it
  /// needs — opening connections, restoring a credential, starting
  /// timers — starting with `await super.initialize();`, so the two never
  /// happen in the wrong order. That override never has to guard against a
  /// second call itself: reaching [isInitialized] here already means this
  /// call did nothing, so nothing an override adds afterwards should either —
  /// the same way [Sdk] itself checks before doing its own work.
  ///
  /// Calling it twice must be harmless, because a host that recovers from a
  /// failed start will call it again.
  @mustCallSuper
  Future<void> initialize() async {
    if (isInitialized) return;
    _isInitialized = true;
    _instances[runtimeType] = this;
  }

  /// Releases everything [initialize] took.
  ///
  /// Does nothing when this instance was never [isInitialized]. Otherwise
  /// forgets its registration. Unregisters `this` from [instance] unless a
  /// newer instance of the same type already replaced it — a backend swap
  /// that never disposed the one it replaced must not cost the new one its
  /// own registration. An override releases whatever else it opened, and
  /// must be safe to call on an implementation that was never initialised,
  /// and safe to call twice, since it runs on paths that are already going
  /// wrong.
  @mustCallSuper
  Future<void> dispose() async {
    if (!isInitialized) return;
    _isInitialized = false;

    if (identical(_instances[runtimeType], this)) {
      _instances.remove(runtimeType);
    }
  }
}

/// An [Sdk] that keeps everything on the device.
///
/// Extend it for an implementation with nothing to reach over the network.
base class LocalSdk extends Sdk {}

/// An [Sdk] that reaches a server over REST.
///
/// Extend it for an implementation that talks to an API, and hand it the client
/// every call goes through. The nodes it builds for its ports are made from that
/// client, so a project states where the server is once.
///
/// ```dart
/// final class MySdk extends RestSdk {
///   MySdk() : super(RestClient(...));
///
///   late final Users users = Users(RestNode(client));
/// }
/// ```
abstract base class RestSdk extends Sdk {
  /// Makes an implementation that sends every call through [client].
  RestSdk(RestClient client) : _client = client;

  final RestClient _client;

  /// The client every REST call of this implementation goes through.
  ///
  /// For the implementation to build its nodes from, and not reachable from
  /// anywhere else: what the rest of the app gets are the ports. It cannot be
  /// overridden, since the one given to the constructor is the one to use.
  @protected
  @nonVirtual
  RestClient get client => _client;
}

/// An [Sdk] that reaches an external service through a vendor's own package.
///
/// Extend it for an implementation that wraps Firebase, Supabase or a company's
/// own client rather than pylon's own `RestClient`.
base class VendorSdk extends Sdk {}
