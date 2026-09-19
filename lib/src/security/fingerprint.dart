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

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:meta/meta.dart';

/// Where the fingerprint is kept between launches.
///
/// [PlatformSecretStore] is the one an app uses: the operating system's own
/// vault. Another one exists for a test.
abstract interface class SecretStore {
  /// The secret kept under [name], or `null` when none was ever written.
  ///
  /// A store that cannot answer throws. That is never to be read as "no
  /// secret": a new one would then replace the real one, and everything the
  /// real one protects would be lost.
  Future<String?> read(String name);

  /// Keeps [value] under [name], replacing what was there.
  Future<void> write(String name, String value);
}

/// The operating system's vault: the Keychain on iOS and macOS, the Keystore
/// behind encrypted preferences on Android.
///
/// It is set up as strictly as the platform allows, and for the one thing that
/// matters here:
///
/// - **iOS and macOS**: readable once the device was unlocked after boot, and
///   only on this device — never synchronised to another one, never restored
///   from a backup onto another.
/// - **Android**: `resetOnError` is off. The plugin's default deletes what it
///   cannot decrypt, which would quietly throw the fingerprint away, mint a new
///   one, and orphan the encrypted database.
///
/// Nothing is written to a file this package could have made itself.
final class PlatformSecretStore implements SecretStore {
  /// Uses the operating system's vault.
  const PlatformSecretStore()
    : _storage = const FlutterSecureStorage(
        iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
        aOptions: AndroidOptions(resetOnError: false),
        mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
      );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String name) => _storage.read(key: name);

  @override
  Future<void> write(String name, String value) => _storage.write(key: name, value: value);
}

/// What went wrong keeping or reading the fingerprint.
final class FingerprintError implements Exception {
  /// Explains [message].
  const FingerprintError(this.message);

  /// What happened, without ever containing the fingerprint.
  final String message;

  @override
  String toString() => 'FingerprintError($message)';
}

/// The secret only this installation of the app holds: 256 random bits,
/// created the first time the app runs, kept in the operating system's vault,
/// and never shown to anyone, this class's own callers included.
///
/// Nothing hands the secret out. What comes out of it is derived from it, one
/// derivation per purpose, so a key made for the database is unrelated to one
/// made for anything else, and learning one says nothing of the others:
///
/// ```dart
/// final key = Fingerprint.instance.derive('database');
/// ```
///
/// The fingerprint is what the database file is encrypted with, so that a copy
/// of the `.db` file taken off the device cannot be read, and what a call must
/// present to reach the whole database instead of one tenant's part of it.
///
/// What this guarantees, and what it does not. The secret comes from the
/// operating system's cryptographic random source, is 256 bits long, and is
/// only ever in memory or in the vault, so it cannot be guessed and is not in
/// any file to copy. It does not stop code running inside this app from asking
/// for a derivation: the app is trusted. And on a device where the vault gives
/// way, the fingerprint goes with it.
///
/// It is registered by `configureSdk`, first of everything, and reachable as
/// [instance] afterwards.
@Singleton(order: -2)
final class Fingerprint {
  Fingerprint._(this._secret);

  /// A fresh fingerprint, for a test or a throwaway database.
  ///
  /// It is not stored anywhere. The one an app uses is [instance].
  factory Fingerprint.generate([Random? random]) => Fingerprint._(_randomBytes(random ?? Random.secure()));

  /// The name the secret is kept under in the vault.
  @visibleForTesting
  static const storedName = 'pylon.fingerprint.v1';

  static const int _length = 32;
  static final Expando<Future<Fingerprint>> _loading = Expando<Future<Fingerprint>>();

  final Uint8List _secret;

  /// Resolves the [Fingerprint] `configureSdk` registers.
  @FactoryMethod(preResolve: true)
  static Future<Fingerprint> initialize() => load();

  /// The registered fingerprint. Throws from `GetIt` when `configureSdk` has
  /// not run.
  static Fingerprint get instance => GetIt.instance<Fingerprint>();

  /// Wipes the secret from memory when `GetIt.reset` lets go of it.
  @disposeMethod
  void dispose() => _secret.fillRange(0, _secret.length, 0);

  /// Reads the fingerprint from [store], creating and keeping one when the
  /// store has none — which is only the first time the app runs.
  ///
  /// A record that is there but is not a fingerprint throws a
  /// [FingerprintError] and is left alone; so does a store that fails, or that
  /// does not give back what was just written. Replacing the fingerprint is
  /// never a way of recovering: whatever it encrypted would be lost for good.
  ///
  /// Two calls at once on one [store] share the same creation.
  static Future<Fingerprint> load({SecretStore? store, Random? random}) {
    final vault = store ?? const PlatformSecretStore();
    return _loading[vault] ??= _load(vault, random ?? Random.secure()).whenComplete(() => _loading[vault] = null);
  }

  static Future<Fingerprint> _load(SecretStore store, Random random) async {
    final stored = await store.read(storedName);
    if (stored != null) return Fingerprint._(_decode(stored));

    final created = _randomBytes(random);
    final encoded = base64Url.encode(created);
    await store.write(storedName, encoded);
    final kept = await store.read(storedName);
    if (kept != encoded) {
      throw const FingerprintError('the vault did not keep the fingerprint it was given');
    }
    return Fingerprint._(created);
  }

  static Uint8List _decode(String stored) {
    final Uint8List bytes;
    try {
      bytes = base64Url.decode(stored);
    } on FormatException {
      throw const FingerprintError('the stored fingerprint is not valid: it was left as it is');
    }
    if (bytes.length != _length) {
      throw const FingerprintError('the stored fingerprint has the wrong length: it was left as it is');
    }
    return bytes;
  }

  static Uint8List _randomBytes(Random random) =>
      Uint8List.fromList([for (var i = 0; i < _length; i++) random.nextInt(256)]);

  /// [length] bytes derived from this fingerprint for [purpose], with HKDF
  /// (RFC 5869) over SHA-256.
  ///
  /// The same purpose always gives the same bytes, and two purposes give
  /// bytes with nothing in common. Use one purpose per use.
  Uint8List derive(String purpose, {int length = 32}) {
    if (purpose.isEmpty) throw ArgumentError.value(purpose, 'purpose', 'cannot be empty');
    return hkdfSha256(_secret, salt: _salt, info: utf8.encode('pylon/derive/v1/$purpose'), length: length);
  }

  /// [derive], as lower-case hexadecimal text, for a key that is given as text.
  String deriveHex(String purpose, {int length = 32}) =>
      derive(purpose, length: length).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  /// Whether [other] is the same fingerprint, compared in a time that does not
  /// depend on where they first differ.
  bool matches(Fingerprint other) {
    if (_secret.length != other._secret.length) return false;
    var difference = 0;
    for (var i = 0; i < _secret.length; i++) {
      difference |= _secret[i] ^ other._secret[i];
    }
    return difference == 0;
  }

  static final Uint8List _salt = Uint8List.fromList(utf8.encode('pylon.fingerprint.salt.v1'));

  /// Never shows the secret.
  @override
  String toString() => 'Fingerprint(hidden)';
}

/// HKDF (RFC 5869) with HMAC-SHA-256: [length] bytes of key material from
/// [ikm], bound to [info] and, optionally, [salt].
///
/// Public only so that a test can check it against the RFC's own vectors.
@visibleForTesting
Uint8List hkdfSha256(List<int> ikm, {List<int>? salt, List<int> info = const [], required int length}) {
  if (length < 1 || length > 255 * 32) throw RangeError.range(length, 1, 255 * 32, 'length');
  final extracted = Hmac(sha256, salt == null || salt.isEmpty ? Uint8List(32) : salt).convert(ikm).bytes;
  final expander = Hmac(sha256, extracted);
  final output = BytesBuilder();
  var block = <int>[];
  for (var counter = 1; output.length < length; counter++) {
    block = expander.convert([...block, ...info, counter]).bytes;
    output.add(block);
  }
  return Uint8List.fromList(output.toBytes().sublist(0, length));
}
