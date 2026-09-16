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

/// The plug.
///
/// An [Sdk] is one implementation of everything a project's contract needs. It
/// declares no operations here, because the operations are the project's and
/// pylon must not know a single one of them: the project writes its own
/// interface listing the ports it has, and requires implementations of it to
/// also implement [Sdk], so they get a lifetime.
///
/// ```dart
/// abstract interface class MySdkBackend implements Sdk {
///   BrandPort get brand;
///   StorePort get store;
/// }
/// ```
///
/// That is the whole trick. What crosses the boundary is the project's own
/// interface; what pylon adds is the two moments every implementation has, the
/// one where it wires itself up and the one where it lets go.
abstract interface class Sdk {
  /// What this implementation talks to, for logs and for error messages.
  ///
  /// Short and stable: `rest`, `firebase`, `memory`. It ends up in the message a
  /// developer reads when something is not wired the way they thought.
  String get name;

  /// Wires this implementation up and makes it usable.
  ///
  /// Everything it needs and cannot obtain lazily happens here: opening
  /// connections, restoring a credential, starting timers. Calling it twice must
  /// be harmless, because a host that recovers from a failed start will call it
  /// again.
  Future<void> initialize();

  /// Releases everything [initialize] took.
  ///
  /// Must be safe to call on an implementation that was never initialised, and
  /// safe to call twice, since it runs on paths that are already going wrong.
  Future<void> dispose();
}
