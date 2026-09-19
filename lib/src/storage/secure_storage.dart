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

/// The secret only this installation of the app holds: 256 random bits,
/// created the first time the app runs and kept in the operating system's
/// vault, and never shown to anyone, this class's own callers included.
///
/// Nothing hands the secret out. What comes out of it is derived from it, one
/// derivation per purpose, so a key made for the database is unrelated to one
/// made for anything else, and learning one says nothing of the others:
///
/// ```dart
/// final key = SecureStorage.fingerprint.derive('database');
/// ```
///
/// It is what the database file is encrypted with, so that a copy of the `.db`
/// taken off the device cannot be read, and what a call must present to reach
/// the whole database instead of one tenant's part of it.
///
/// The secret comes from the operating system's cryptographic random source
/// and is only ever in memory or in the vault, so it cannot be guessed and is
/// in no file to copy. It does not stop code running inside this app from
/// asking for a derivation: the app is trusted. And on a device where the vault
/// gives way, the fingerprint goes with it.
final class Fingerprint {
  Fingerprint._(this._secret);

  /// A fresh fingerprint, kept nowhere, for a test. The one an app uses is
  /// [SecureStorage.fingerprint].
  @visibleForTesting
  factory Fingerprint.generate([Random? random]) => Fingerprint._(_randomBytes(random ?? Random.secure()));

  static const int _length = 32;
  static final Uint8List _salt = Uint8List.fromList(utf8.encode('pylon.fingerprint.salt.v1'));

  final Uint8List _secret;

  void _wipe() => _secret.fillRange(0, _secret.length, 0);

  /// [length] bytes derived from this fingerprint for [purpose], with HKDF
  /// (RFC 5869) over SHA-256.
  ///
  /// The same purpose always gives the same bytes, and two purposes give bytes
  /// with nothing in common. Use one purpose per use.
  Uint8List derive(String purpose, {int length = 32}) {
    if (purpose.isEmpty) throw ArgumentError.value(purpose, 'purpose', 'cannot be empty');
    return _hkdf(_secret, _salt, utf8.encode('pylon/derive/v1/$purpose'), length);
  }

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

  /// Never shows the secret.
  @override
  String toString() => 'Fingerprint(hidden)';
}

Uint8List _randomBytes(Random random) =>
    Uint8List.fromList([for (var i = 0; i < Fingerprint._length; i++) random.nextInt(256)]);

/// HKDF (RFC 5869) with HMAC-SHA-256.
Uint8List _hkdf(List<int> ikm, List<int> salt, List<int> info, int length) {
  if (length < 1 || length > 255 * 32) throw RangeError.range(length, 1, 255 * 32, 'length');
  final expander = Hmac(sha256, Hmac(sha256, salt).convert(ikm).bytes);
  final output = BytesBuilder();
  var block = <int>[];
  for (var counter = 1; output.length < length; counter++) {
    block = expander.convert([...block, ...info, counter]).bytes;
    output.add(block);
  }
  return Uint8List.fromList(output.toBytes().sublist(0, length));
}

/// A project's own secrets — a token, a key, a credential — read and written
/// through the operating system's vault, next to the app's [Fingerprint].
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
/// entry answers at once, like a `Preference`; a write goes to the vault first, and
/// the entry only changes — and only tells its listeners — once the vault has
/// kept it. A stored value that no longer decodes is answered with the entry's
/// default.
///
/// The fingerprint is not an entry: it is [fingerprint], made the first time the
/// app runs and kept for good, and no entry can read, replace or clear it. Keys
/// that start with `pylon.` are the package's own and are refused to an entry.
@Singleton(order: -2)
class SecureStorage {
  SecureStorage._(this._values, this._fingerprint);

  final Map<String, String> _values;
  final Fingerprint _fingerprint;

  /// The operating system's vault, set up as strictly as the platform allows:
  /// on iOS and macOS readable once the device was unlocked after boot and only
  /// on this device, never synchronised to another; on Android with
  /// `resetOnError` off, since the plugin's default deletes what it cannot
  /// decrypt, which would quietly throw the fingerprint away, mint a new one,
  /// and orphan the encrypted database.
  static const FlutterSecureStorage _vault = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
    aOptions: AndroidOptions(resetOnError: false),
    mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  static const String _fingerprintName = 'pylon.fingerprint.v1';
  static const String _reservedPrefix = 'pylon.';

  /// Resolves the [SecureStorage] `configureSdk` registers.
  ///
  /// Marked [FactoryMethod.preResolve] so `configureSdk` awaits it before
  /// registering the result, rather than handing out a half-resolved instance.
  ///
  /// Reads everything the vault holds and creates and keeps the fingerprint when
  /// it has none, which is only the first time the app runs. A vault that fails
  /// stops the launch, and so does a fingerprint record that is there but is
  /// not one, or a vault that does not give back what was just written, each
  /// with a [StateError]: a new fingerprint is never the way out of any of them,
  /// since whatever the old one encrypted would be lost for good.
  @FactoryMethod(preResolve: true)
  static Future<SecureStorage> initialize() async {
    final values = {...await _vault.readAll()};
    final stored = values.remove(_fingerprintName);
    if (stored != null) return SecureStorage._(values, Fingerprint._(_decode(stored)));

    final created = _randomBytes(Random.secure());
    final encoded = base64Url.encode(created);
    await _vault.write(key: _fingerprintName, value: encoded);
    if (await _vault.read(key: _fingerprintName) != encoded) {
      throw StateError('The vault did not keep the fingerprint it was given.');
    }
    return SecureStorage._(values, Fingerprint._(created));
  }

  static Uint8List _decode(String stored) {
    try {
      final bytes = base64Url.decode(stored);
      if (bytes.length == Fingerprint._length) return bytes;
    } on FormatException {
      // falls through to the same refusal
    }
    throw StateError('The stored fingerprint is not valid: it was left as it is.');
  }

  static SecureStorage get _instance => GetIt.instance<SecureStorage>();

  /// The app's fingerprint, on the registered [SecureStorage].
  static Fingerprint get fingerprint => _instance._fingerprint;

  /// Wipes what is held in memory when `GetIt.reset` lets go of it: the
  /// fingerprint, and every secret read from the vault. The vault itself keeps
  /// them.
  @disposeMethod
  void dispose() {
    _fingerprint._wipe();
    _values.clear();
  }

  /// An entry holding a [String], on the registered [SecureStorage].
  static Secure<String> string_(String key, String defaultValue) => _SecureString(_instance, key, defaultValue);

  /// An entry holding bytes, stored as text, on the registered [SecureStorage].
  static Secure<Uint8List> bytes_(String key, Uint8List defaultValue) => _SecureBytes(_instance, key, defaultValue);

  /// An entry holding an [int], on the registered [SecureStorage].
  static Secure<int> int_(String key, int defaultValue) => _SecureInt(_instance, key, defaultValue);

  /// An entry holding a [bool], on the registered [SecureStorage].
  static Secure<bool> bool_(String key, bool defaultValue) => _SecureBool(_instance, key, defaultValue);

  /// Keeps [value] under [key] in the vault, or forgets [key] when [value] is
  /// `null`, and only then updates what is held in memory.
  Future<void> _write(String key, String? value) async {
    if (value == null) {
      await _vault.delete(key: key);
      _values.remove(key);
    } else {
      await _vault.write(key: key, value: value);
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
/// Never constructed directly: [SecureStorage.string_], [SecureStorage.bytes_],
/// [SecureStorage.int_] and [SecureStorage.bool_] are the only ways to declare
/// one, each fixing which shape it reads and writes so a project never has to
/// name (or get wrong) the private class actually backing it.
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

  /// Decodes what the vault holds for this entry, the default when nothing, or
  /// when what is held no longer decodes. Runs exactly once, to seed
  /// [_valueSubject]: every read after that answers from the cache, kept in step
  /// by [set].
  T _fetch() {
    final stored = _storage._values[_key];
    if (stored == null) return _defaultValue;
    try {
      return _decode(stored) ?? _defaultValue;
    } on FormatException {
      return _defaultValue;
    }
  }

  /// The value [stored] holds, or `null` when it holds none.
  T? _decode(String stored);

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

  /// Forgets the value in the vault and publishes the default on [stream].
  Future<void> clear() async {
    await _storage._write(_key, null);
    if (!_valueSubject.isClosed) _valueSubject.add(_defaultValue);
  }

  /// Closes [stream] for every listener.
  Future<void> dispose() => _valueSubject.close();
}

/// The [Secure] behind [SecureStorage.string_].
final class _SecureString extends Secure<String> {
  _SecureString(super.storage, super.key, super.defaultValue) : super._();

  @override
  String _decode(String stored) => stored;

  @override
  String _encode(String value) => value;
}

/// The [Secure] behind [SecureStorage.bytes_].
final class _SecureBytes extends Secure<Uint8List> {
  _SecureBytes(super.storage, super.key, super.defaultValue) : super._();

  @override
  Uint8List _decode(String stored) => base64Url.decode(stored);

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

/// The [Secure] behind [SecureStorage.int_].
final class _SecureInt extends Secure<int> {
  _SecureInt(super.storage, super.key, super.defaultValue) : super._();

  @override
  int? _decode(String stored) => int.tryParse(stored);

  @override
  String _encode(int value) => '$value';
}

/// The [Secure] behind [SecureStorage.bool_].
final class _SecureBool extends Secure<bool> {
  _SecureBool(super.storage, super.key, super.defaultValue) : super._();

  @override
  bool? _decode(String stored) => switch (stored) {
    'true' => true,
    'false' => false,
    _ => null,
  };

  @override
  String _encode(bool value) => '$value';
}
