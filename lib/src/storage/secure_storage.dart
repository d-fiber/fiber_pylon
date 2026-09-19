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
import 'package:rxdart/rxdart.dart';

import '../common/observable.dart';
import '../common/reporter.dart';

/// Where the secrets are kept between launches.
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

  /// Every secret kept, by name.
  Future<Map<String, String>> readAll();

  /// Keeps [value] under [name], replacing what was there.
  Future<void> write(String name, String value);

  /// Forgets what is kept under [name]. Forgetting what is not there is fine.
  Future<void> delete(String name);
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
  Future<Map<String, String>> readAll() => _storage.readAll();

  @override
  Future<void> write(String name, String value) => _storage.write(key: name, value: value);

  @override
  Future<void> delete(String name) => _storage.delete(key: name);
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
/// created the first time the app runs, kept in the operating system's vault
/// by [SecureStorage], and never shown to anyone, this class's own callers
/// included.
///
/// Nothing hands the secret out. What comes out of it is derived from it, one
/// derivation per purpose, so a key made for the database is unrelated to one
/// made for anything else, and learning one says nothing of the others:
///
/// ```dart
/// final key = SecureStorage.fingerprint.derive('database');
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
final class Fingerprint {
  Fingerprint._(this._secret);

  /// A fresh fingerprint, for a test or a throwaway database.
  ///
  /// It is not stored anywhere. The one an app uses is
  /// [SecureStorage.fingerprint].
  factory Fingerprint.generate([Random? random]) => Fingerprint._(_randomBytes(random ?? Random.secure()));

  static const int _length = 32;

  final Uint8List _secret;

  /// Wipes the secret from memory.
  void dispose() => _secret.fillRange(0, _secret.length, 0);

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

Uint8List _randomBytes(Random random) =>
    Uint8List.fromList([for (var i = 0; i < Fingerprint._length; i++) random.nextInt(256)]);

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

/// A project's own secrets — a token, a key, a credential — read and written
/// through the operating system's vault, and the app's [Fingerprint].
///
/// [SecureStorage] itself is registered `@Singleton(order: -2)`, resolved the
/// moment a project's own `configureSdk` (generated by `injectable`) runs,
/// first of everything: the app database is opened with the fingerprint it
/// holds, so it has to exist before it.
///
/// From then on, a project declares one entry per secret anywhere, through
/// whichever of [SecureStorage]'s own static factories matches the stored
/// type — [string_], [bytes_], [int_] or [bool_] — without holding a
/// [SecureStorage] reference of its own:
///
/// ```dart
/// class AppSecrets {
///   late final refreshToken = SecureStorage.string_('refresh_token', '');
///   late final pin = SecureStorage.bytes_('pin_hash', Uint8List(0));
/// }
/// ```
///
/// Everything the vault holds is read once, when `configureSdk` runs, so an
/// entry answers at once, like a [Valkery]; a write goes to the vault first,
/// and the entry only changes — and only tells its listeners — once the vault
/// has kept it.
///
/// The fingerprint is not an entry: it is [fingerprint], made the first time
/// the app runs and kept for good. Keys that start with `pylon.` are the
/// package's own and are refused to an entry.
@Singleton(order: -2)
class SecureStorage {
  SecureStorage._(this._vault, this._values, this._fingerprint);

  final SecretStore _vault;
  final Map<String, String> _values;
  final Fingerprint _fingerprint;

  /// The name the fingerprint is kept under in the vault.
  @visibleForTesting
  static const fingerprintName = 'pylon.fingerprint.v1';

  static const String _reservedPrefix = 'pylon.';
  static final Expando<Future<SecureStorage>> _loading = Expando<Future<SecureStorage>>();

  /// Resolves the [SecureStorage] `configureSdk` registers.
  ///
  /// Marked [FactoryMethod.preResolve] so `configureSdk` awaits it before
  /// registering the result, rather than handing out a half-resolved instance.
  @FactoryMethod(preResolve: true)
  static Future<SecureStorage> initialize() => load();

  /// Reads everything [store] holds — the operating system's vault unless
  /// another is given — and creates and keeps the fingerprint when it has none,
  /// which is only the first time the app runs.
  ///
  /// A fingerprint record that is there but is not one throws a
  /// [FingerprintError] and is left alone; so does a store that fails, or that
  /// does not give back what was just written. Replacing the fingerprint is
  /// never a way of recovering: whatever it encrypted would be lost for good.
  ///
  /// Two calls at once on one [store] share the same creation.
  static Future<SecureStorage> load({SecretStore? store, Random? random}) {
    final vault = store ?? const PlatformSecretStore();
    return _loading[vault] ??= _load(vault, random ?? Random.secure()).whenComplete(() => _loading[vault] = null);
  }

  static Future<SecureStorage> _load(SecretStore vault, Random random) async {
    final values = {...await vault.readAll()};
    final stored = values.remove(fingerprintName);
    if (stored != null) return SecureStorage._(vault, values, Fingerprint._(_decode(stored)));

    final created = _randomBytes(random);
    final encoded = base64Url.encode(created);
    await vault.write(fingerprintName, encoded);
    if (await vault.read(fingerprintName) != encoded) {
      throw const FingerprintError('the vault did not keep the fingerprint it was given');
    }
    return SecureStorage._(vault, values, Fingerprint._(created));
  }

  static Uint8List _decode(String stored) {
    final Uint8List bytes;
    try {
      bytes = base64Url.decode(stored);
    } on FormatException {
      throw const FingerprintError('the stored fingerprint is not valid: it was left as it is');
    }
    if (bytes.length != Fingerprint._length) {
      throw const FingerprintError('the stored fingerprint has the wrong length: it was left as it is');
    }
    return bytes;
  }

  static SecureStorage get _instance => GetIt.instance<SecureStorage>();

  /// The app's fingerprint, on the registered [SecureStorage]. Throws from
  /// `GetIt` when `configureSdk` has not run.
  static Fingerprint get fingerprint => _instance._fingerprint;

  /// The fingerprint this storage holds, for what is inside the package.
  @internal
  Fingerprint get loadedFingerprint => _fingerprint;

  /// Wipes what is held in memory when `GetIt.reset` lets go of it: the
  /// fingerprint, and every secret read from the vault. The vault itself keeps
  /// them.
  @disposeMethod
  void dispose() {
    _fingerprint.dispose();
    _values.clear();
  }

  /// An entry holding a [String], on the registered [SecureStorage].
  static Secure<String> string_(String key, String defaultValue) => Secure.string_(_instance, key, defaultValue);

  /// An entry holding bytes, stored as text, on the registered
  /// [SecureStorage]. A stored value that no longer decodes is reported to
  /// [reporter] and answered with [defaultValue].
  static Secure<Uint8List> bytes_(String key, Uint8List defaultValue, {Reporter reporter = const SilentReporter()}) =>
      Secure.bytes_(_instance, key, defaultValue, reporter: reporter);

  /// An entry holding an [int], on the registered [SecureStorage]. A stored
  /// value that no longer decodes is reported to [reporter] and answered with
  /// [defaultValue].
  static Secure<int> int_(String key, int defaultValue, {Reporter reporter = const SilentReporter()}) =>
      Secure.int_(_instance, key, defaultValue, reporter: reporter);

  /// An entry holding a [bool], on the registered [SecureStorage]. A stored
  /// value that no longer decodes is reported to [reporter] and answered with
  /// [defaultValue].
  static Secure<bool> bool_(String key, bool defaultValue, {Reporter reporter = const SilentReporter()}) =>
      Secure.bool_(_instance, key, defaultValue, reporter: reporter);

  /// Keeps [value] under [key] in the vault, or forgets [key] when [value] is
  /// `null`, and only then updates what is held in memory.
  Future<void> _write(String key, String? value) async {
    if (value == null) {
      await _vault.delete(key);
      _values.remove(key);
    } else {
      await _vault.write(key, value);
      _values[key] = value;
    }
  }

  void _requireOwnKey(String key) {
    if (key.isEmpty) throw ArgumentError.value(key, 'key', 'cannot be empty');
    if (key.startsWith(_reservedPrefix)) {
      throw ArgumentError.value(key, 'key', 'starts with "$_reservedPrefix", which is the package\'s own');
    }
  }
}

/// One entry of a [SecureStorage], read and written in the vault as text.
///
/// Never constructed directly: [string_], [bytes_], [int_] and [bool_] are the
/// only ways to declare one, each fixing which shape it reads and writes so a
/// project never has to name (or get wrong) the private class actually
/// backing it.
sealed class Secure<T> extends Observable<T> {
  final SecureStorage _storage;
  final String _key;
  final T _defaultValue;

  /// Seeded once, lazily, from [_fetch] — the moment something first reads
  /// [value], [call] or [stream], not before, so the read never runs ahead of a
  /// subclass's own fields still being set.
  late final BehaviorSubject<T> _valueSubject = BehaviorSubject<T>.seeded(_fetch());

  Secure._(this._storage, this._key, this._defaultValue) {
    _storage._requireOwnKey(_key);
  }

  /// An entry holding a [String].
  static Secure<String> string_(SecureStorage storage, String key, String defaultValue) =>
      _SecureString(storage, key, defaultValue);

  /// An entry holding bytes, stored as text.
  static Secure<Uint8List> bytes_(
    SecureStorage storage,
    String key,
    Uint8List defaultValue, {
    Reporter reporter = const SilentReporter(),
  }) => _SecureBytes(storage, key, defaultValue, reporter: reporter);

  /// An entry holding an [int].
  static Secure<int> int_(
    SecureStorage storage,
    String key,
    int defaultValue, {
    Reporter reporter = const SilentReporter(),
  }) => _SecureInt(storage, key, defaultValue, reporter: reporter);

  /// An entry holding a [bool].
  static Secure<bool> bool_(
    SecureStorage storage,
    String key,
    bool defaultValue, {
    Reporter reporter = const SilentReporter(),
  }) => _SecureBool(storage, key, defaultValue, reporter: reporter);

  /// The key this entry occupies in the vault.
  String get key => _key;

  /// What answers a key nothing has written to yet.
  T get defaultValue => _defaultValue;

  @override
  T get value => _valueSubject.value;

  /// The current value, same as [value] — lets an entry be read by calling it
  /// directly, `token()` rather than `token.value`.
  T call() => _valueSubject.value;

  /// Unlike [Observable.stream]'s own contract, this replays the current value
  /// to every new listener before anything that changes after: it is backed by
  /// a [BehaviorSubject], which always does.
  @override
  Stream<T> get stream => _valueSubject.stream;

  /// Same as [stream]: already the current value followed by every change.
  @override
  Stream<T> get values => stream;

  /// Decodes what the vault holds for this entry, [_defaultValue] when nothing.
  /// Runs exactly once, to seed [_valueSubject]: every read after that answers
  /// from the cache, kept in step by [set].
  T _fetch();

  /// This entry's value as the text the vault keeps.
  String _encode(T value);

  /// Whether [a] and [b] are the same value, so writing one over the other is
  /// not worth a trip to the vault.
  bool _same(T a, T b) => a == b;

  /// Keeps [next] in the vault, and only once it has, makes it the value and
  /// publishes it on [stream]. A vault that refuses throws, and the entry is
  /// left as it was.
  ///
  /// Ignored when [next] already equals [value].
  Future<void> set(T next) async {
    if (_same(next, value)) return;
    await _storage._write(_key, _encode(next));
    if (!_valueSubject.isClosed) _valueSubject.add(next);
  }

  /// Forgets the value in the vault and publishes [defaultValue] on [stream].
  Future<void> clear() async {
    await _storage._write(_key, null);
    if (!_valueSubject.isClosed) _valueSubject.add(_defaultValue);
  }

  /// Closes [stream] for every listener.
  Future<void> dispose() => _valueSubject.close();
}

/// The [Secure] behind [Secure.string_].
final class _SecureString extends Secure<String> {
  _SecureString(super.storage, super.key, super.defaultValue) : super._();

  @override
  String _fetch() => _storage._values[key] ?? defaultValue;

  @override
  String _encode(String value) => value;
}

/// The [Secure] behind [Secure.bytes_].
final class _SecureBytes extends Secure<Uint8List> {
  _SecureBytes(super.storage, super.key, super.defaultValue, {required Reporter reporter})
    : _reporter = reporter,
      super._();

  final Reporter _reporter;

  @override
  Uint8List _fetch() {
    final stored = _storage._values[key];
    if (stored == null) return defaultValue;
    try {
      return base64Url.decode(stored);
    } catch (error, stackTrace) {
      _reporter.recordError(error, stackTrace, context: {'secret': key});
      return defaultValue;
    }
  }

  @override
  String _encode(Uint8List value) => base64Url.encode(value);

  @override
  bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The [Secure] behind [Secure.int_].
final class _SecureInt extends Secure<int> {
  _SecureInt(super.storage, super.key, super.defaultValue, {required Reporter reporter})
    : _reporter = reporter,
      super._();

  final Reporter _reporter;

  @override
  int _fetch() {
    final stored = _storage._values[key];
    if (stored == null) return defaultValue;
    final parsed = int.tryParse(stored);
    if (parsed != null) return parsed;
    _reporter.recordError(FormatException('not an int', stored), StackTrace.current, context: {'secret': key});
    return defaultValue;
  }

  @override
  String _encode(int value) => '$value';
}

/// The [Secure] behind [Secure.bool_].
final class _SecureBool extends Secure<bool> {
  _SecureBool(super.storage, super.key, super.defaultValue, {required Reporter reporter})
    : _reporter = reporter,
      super._();

  final Reporter _reporter;

  @override
  bool _fetch() {
    final stored = _storage._values[key];
    if (stored == null) return defaultValue;
    if (stored == 'true') return true;
    if (stored == 'false') return false;
    _reporter.recordError(FormatException('not a bool', stored), StackTrace.current, context: {'secret': key});
    return defaultValue;
  }

  @override
  String _encode(bool value) => '$value';
}
