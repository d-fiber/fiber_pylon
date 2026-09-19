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

import '../common/reporter.dart';
import '../storage/secure_storage.dart';

/// Where the credential survives a restart.
///
/// A store of its own rather than a setting, because a credential is a secret
/// and the place a project keeps its preferences is not one: what sits in them
/// can be read off the device by anyone who copies the app's files. [StoredCredential]
/// is the store to use, and it keeps the credential in the operating system's
/// vault.
abstract interface class CredentialStore<C extends Object> {
  /// The stored credential, or `null` when there is none.
  Future<C?> read();

  /// Stores [credential], replacing whatever was there.
  Future<void> write(C credential);

  /// Removes the stored credential.
  Future<void> clear();
}

/// A [CredentialStore] that forgets everything when the process ends.
///
/// What a test runs against, and what a backend holding no credentials of its
/// own uses.
class MemoryCredentialStore<C extends Object> implements CredentialStore<C> {
  C? _credential;

  /// Starts out holding [initial], which defaults to nothing.
  MemoryCredentialStore([C? initial]) : _credential = initial;

  @override
  Future<C?> read() async => _credential;

  @override
  Future<void> write(C credential) async {
    _credential = credential;
  }

  @override
  Future<void> clear() async {
    _credential = null;
  }
}

/// A [CredentialStore] backed by a [Secure] entry, which keeps the credential in
/// the operating system's vault.
///
/// The project supplies [encode] and [decode], so the stored shape is entirely
/// its own: pylon writes the string it is handed and never looks at it. A
/// credential that fails to decode is reported and read back as absent rather
/// than thrown, because this runs at startup and a shape that changed between
/// two versions of an app must not stop it from opening.
///
/// ```dart
/// final store = StoredCredential<Ticket>(
///   SecureStorage.string_('ticket', ''),
///   encode: (ticket) => ticket.serialise(),
///   decode: Ticket.parse,
/// );
/// ```
class StoredCredential<C extends Object> implements CredentialStore<C> {
  final Secure<String> _entry;
  final String Function(C credential) _encode;
  final C Function(String raw) _decode;
  final Reporter _reporter;

  /// Stores the credential in [entry], which is declared with
  /// [SecureStorage.string_] and reads as an empty string while nothing is kept.
  StoredCredential(
    Secure<String> entry, {
    required String Function(C credential) encode,
    required C Function(String raw) decode,
    Reporter reporter = const SilentReporter(),
  }) : _entry = entry,
       _encode = encode,
       _decode = decode,
       _reporter = reporter;

  @override
  Future<C?> read() async {
    final raw = _entry.value;
    if (raw.isEmpty) return null;
    try {
      return _decode(raw);
    } catch (error, stackTrace) {
      _reporter.recordError(error, stackTrace, context: {'credential': _entry.key});
      return null;
    }
  }

  @override
  Future<void> write(C credential) => _entry.set(_encode(credential));

  @override
  Future<void> clear() => _entry.clear();
}
