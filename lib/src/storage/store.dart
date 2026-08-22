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

/// Somewhere small strings survive a restart.
///
/// Everything pylon persists goes through this: the session, and whatever
/// preferences the project declares. Reading is synchronous because a caller
/// asking whether it is signed in cannot wait, which means an implementation
/// backed by an asynchronous store loads itself once at startup and serves from
/// memory afterwards. That is how `shared_preferences` already works.
///
/// One type only, because everything else encodes to a string and a store that
/// speaks five types is five things to reimplement per platform.
abstract interface class KeyValueStore {
  /// What is stored under [key], or `null` when nothing is.
  String? read(String key);

  /// Stores [value] under [key], replacing anything already there.
  Future<void> write(String key, String value);

  /// Removes whatever is stored under [key].
  Future<void> delete(String key);
}

/// A [KeyValueStore] that keeps everything in memory.
///
/// What a test runs against, and what a backend with nothing to persist uses.
/// Nothing survives the process.
class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _entries;

  /// Starts out holding [initial], which defaults to nothing.
  MemoryKeyValueStore([Map<String, String> initial = const {}])
    : _entries = Map<String, String>.of(initial);

  @override
  String? read(String key) => _entries[key];

  @override
  Future<void> write(String key, String value) async {
    _entries[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _entries.remove(key);
  }

  /// Every key currently held, for a test to assert on.
  Iterable<String> get keys => _entries.keys;
}
