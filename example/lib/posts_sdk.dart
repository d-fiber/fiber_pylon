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

import 'contract/contract.dart';

/// This example's own entry point, shaped the way a real SDK built on pylon
/// is: call [PostsSdk.initialize] once, reach every operation through
/// [PostsSdk.I].
///
/// ```dart
/// await PostsSdk.initialize(backend: MemoryBackend.new);
///
/// switch (await PostsSdk.I.posts.list()) {
///   case OK(:final data):
///     // data is the posts held
///   case Failure(:final error):
///     // error names why not
/// }
/// ```
///
/// What answers those calls sits behind one [ExampleBackend]. [switchTo] is
/// the one thing this example adds beyond what a real SDK needs: swapping
/// which backend is live without restarting the app, so the swap is
/// something you can watch happen rather than only read that it would.
class PostsSdk {
  static final Singleton<PostsSdk> _handle = Singleton<PostsSdk>('PostsSdk');

  final ExampleBackend _backend;

  /// Reading and listing posts.
  final PostPort posts;

  /// Live changes to the posts this backend holds, or `null` when this
  /// backend cannot offer any.
  final EventsPort? events;

  PostsSdk._(this._backend) : posts = _backend.posts, events = _backend.events;

  /// What this backend is called, and a one-line description of it.
  String get name => _backend.name;

  /// Describes what answers, for a screen to show.
  String get describe => _backend.describe;

  /// The credential this backend keeps alive, or `null` when it needs none.
  CredentialManager<Object, Object>? get credentials => _backend.credentials;

  /// Starts the SDK with [backend].
  ///
  /// Calling this a second time does nothing, so a host recovering from a
  /// failed start can call it again; call [switchTo] to change backend once
  /// the SDK is already running.
  static Future<void> initialize({
    required ExampleBackend Function() backend,
  }) async {
    if (_handle.isSet) return;
    final chosen = backend();
    await chosen.initialize();
    _handle.assign(PostsSdk._(chosen));
  }

  /// The running SDK.
  ///
  /// Throws a [StateError] naming what was not called when [initialize] has
  /// not run.
  static PostsSdk get I => _handle.instance;

  /// Whether [initialize] has run and [shutdown] has not undone it.
  static bool get isRunning => _handle.isSet;

  /// Initialises [backend] and puts it in place of whichever one is running.
  ///
  /// The new backend is fully initialised before the old one is released or
  /// disposed, so a backend that fails to start leaves the SDK exactly as it
  /// was rather than half-swapped.
  static Future<void> switchTo(ExampleBackend Function() backend) async {
    final chosen = backend();
    await chosen.initialize();

    final previous = _handle.orNull?._backend;
    _handle.release();
    _handle.assign(PostsSdk._(chosen));

    await previous?.dispose();
  }

  /// Stops the SDK and releases whatever the backend holds.
  ///
  /// Safe on an SDK that never started, and safe twice.
  static Future<void> shutdown() async {
    final running = _handle.orNull;
    if (running == null) return;
    _handle.release();
    await running._backend.dispose();
  }
}
