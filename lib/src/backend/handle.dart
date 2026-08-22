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

/// Holds the one instance an SDK hands out, and says so when there is none yet.
///
/// Every SDK ends up with the same static getter and the same forgotten call to
/// `initialize`. What makes that painful is not the getter, it is the error: a
/// null dereference three frames deep says nothing about what was forgotten.
///
/// ```dart
/// class MySdk {
///   static final _handle = SdkHandle<MySdk>('MySdk');
///
///   static MySdk get I => _handle.instance;
///
///   static Future<void> initialize({MySdkBackend? backend}) async {
///     if (_handle.isSet) return;
///     final chosen = backend ?? RestBackend(RestConfig.fromEnvironment());
///     await chosen.initialize();
///     _handle.assign(MySdk._(chosen));
///   }
/// }
/// ```
class SdkHandle<T extends Object> {
  /// What the SDK is called, as it appears in the error message.
  final String name;

  T? _instance;

  /// Holds the instance of the SDK called [name].
  SdkHandle(this.name);

  /// Whether an instance has been assigned.
  bool get isSet => _instance != null;

  /// The instance, or `null` when there is none.
  ///
  /// For a caller that has something to do in both cases. A caller that needs
  /// the instance reads [instance] and gets a message instead of a null.
  T? get orNull => _instance;

  /// The instance.
  ///
  /// Throws a [StateError] naming [name] when nothing has been assigned yet,
  /// which is the whole reason this exists.
  T get instance {
    final current = _instance;
    if (current == null) {
      throw StateError(
        '$name is not initialized. Call $name.initialize() before using it.',
      );
    }
    return current;
  }

  /// Takes [value] as the instance.
  ///
  /// Throws a [StateError] when one is already held, because two initialisations
  /// leave half the app talking to the first instance and half to the second,
  /// which is far harder to see than a thrown error. Call [release] first when
  /// replacing one deliberately, as a test does between cases.
  void assign(T value) {
    if (_instance != null) {
      throw StateError(
        '$name is already initialized. Call release() before assigning again.',
      );
    }
    _instance = value;
  }

  /// Forgets the instance, so [assign] can take another.
  ///
  /// Does not dispose it: what was held may be shared, and this has no way of
  /// knowing. The caller disposes.
  void release() {
    _instance = null;
  }
}
