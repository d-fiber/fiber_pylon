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

/// The secret only this installation of the app holds, and the source of every
/// key the app needs.
///
/// The secret itself is never handed out. A feature that needs a key asks for
/// one with a purpose of its own, and two purposes give unrelated keys, so
/// learning one key says nothing about the others:
///
/// ```dart
/// final key = SecureStorage.fingerprint.derive('database');
/// ```
///
/// The database file is encrypted with such a key, so that a copy of the `.db`
/// taken off the device cannot be read. A call also presents the fingerprint to
/// reach the whole database instead of one tenant's part of it.
///
/// It is created the first time the app runs and stays in the operating
/// system's vault. Code running inside the app can still ask for any key, since
/// the app is trusted, and on a device whose vault gives way the fingerprint
/// goes with it.
final class Fingerprint {
  Fingerprint._(this._secret);

  /// A fresh fingerprint kept nowhere, for a test.
  ///
  /// The fingerprint an app uses is [SecureStorage.fingerprint]. [random]
  /// defaults to [Random.secure].
  @visibleForTesting
  factory Fingerprint.generate([Random? random]) => Fingerprint._(_randomBytes(random ?? Random.secure()));

  /// The number of bytes in the secret, which is 256 bits.
  static const int _length = 32;

  /// The fixed salt every derivation starts from.
  static final Uint8List _salt = Uint8List.fromList(utf8.encode('pylon.fingerprint.salt.v1'));

  /// The secret itself, held in memory only.
  final Uint8List _secret;

  void _wipe() => _secret.fillRange(0, _secret.length, 0);

  /// The [length] bytes of key made for [purpose].
  ///
  /// The same purpose always gives the same bytes, so a key can be asked for
  /// again instead of being stored, and two purposes give unrelated bytes, so
  /// each use should have a purpose of its own.
  ///
  /// Throws an [ArgumentError] if [purpose] is empty. Throws a [RangeError] if
  /// [length] is not between 1 and 8160.
  Uint8List derive(String purpose, {int length = 32}) {
    if (purpose.isEmpty) throw ArgumentError.value(purpose, 'purpose', 'cannot be empty');
    return _hkdf(_secret, _salt, utf8.encode('pylon/derive/v1/$purpose'), length);
  }

  /// Whether [other] is the same fingerprint, without revealing through its
  /// timing where they differ.
  bool matches(Fingerprint other) {
    if (_secret.length != other._secret.length) return false;
    var difference = 0;
    for (var i = 0; i < _secret.length; i++) {
      difference |= _secret[i] ^ other._secret[i];
    }
    return difference == 0;
  }

  /// A description of this fingerprint that never shows the secret.
  @override
  String toString() => 'Fingerprint(hidden)';
}

/// The random bytes of a new secret, drawn from [random].
Uint8List _randomBytes(Random random) =>
    Uint8List.fromList([for (var i = 0; i < Fingerprint._length; i++) random.nextInt(256)]);

/// The [length] bytes of key that HKDF (RFC 5869) makes from [ikm], with [salt]
/// and [info], using HMAC over SHA-256.
///
/// Throws a [RangeError] if [length] is not between 1 and 8160, the most HKDF
/// over SHA-256 can give.
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

/// The app's secrets, such as a token, a key or a credential, kept in the
/// operating system's vault.
///
/// A project declares one entry per secret, with the factory that matches its
/// type: [string_], [bytes_], [int_] or [bool_]. There is no storage object to
/// hold or pass around, the factories find it on their own:
///
/// ```dart
/// class AppSecrets {
///   late final refreshToken = SecureStorage.string_('refresh_token', '');
///   late final pin = SecureStorage.bytes_('pin_hash', Uint8List(0));
/// }
/// ```
///
/// Each entry is then read with `refreshToken()` and written with
/// `await refreshToken.set(token)`, see [Secure]. It works like a `Preference`.
///
/// Keys that start with `pylon.` belong to the package, and declaring an entry
/// under one throws an [ArgumentError]. The app's [fingerprint] lives in the same
/// vault but is not an entry: no entry can read, replace or clear it.
///
/// Declare entries only once `configureSdk` has run, since that is what makes
/// the storage available.
@Singleton(order: -2)
class SecureStorage {
  SecureStorage._(this._values, this._fingerprint);

  /// What the vault holds, minus the fingerprint, so that a read never waits.
  final Map<String, String> _values;

  /// Backs [fingerprint].
  final Fingerprint _fingerprint;

  /// The operating system's vault, set up as strictly as the platform allows.
  ///
  /// On iOS and macOS an entry is readable once the device was unlocked after
  /// boot, and only on this device, never synchronised to another. On Android
  /// `resetOnError` is off, because the plugin's default deletes what it cannot
  /// decrypt: the fingerprint would be replaced without a word, and the
  /// database it encrypted could no longer be opened.
  static const FlutterSecureStorage _vault = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
    aOptions: AndroidOptions(resetOnError: false),
    mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  /// The key the fingerprint is kept under in the vault.
  static const String _fingerprintName = 'pylon.fingerprint.v1';

  /// The prefix of the keys reserved for the package.
  static const String _reservedPrefix = 'pylon.';

  /// Prepares the storage for `configureSdk`, creating the fingerprint the
  /// first time the app runs.
  ///
  /// Called by `configureSdk`, never by a project.
  ///
  /// Throws a [StateError], which stops the launch, when the vault or the saved
  /// fingerprint cannot be used. Making a new fingerprint is never the way out,
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

  /// The fingerprint bytes that [stored] holds.
  ///
  /// Throws a [StateError] if [stored] is not base64 of the right length. Text
  /// that is not base64 at all and base64 of the wrong length are refused
  /// alike, and the stored record is left as it is.
  static Uint8List _decode(String stored) {
    try {
      final bytes = base64Url.decode(stored);
      if (bytes.length == Fingerprint._length) return bytes;
      // ignore: empty_catches
    } on FormatException {}
    throw StateError('The stored fingerprint is not valid: it was left as it is.');
  }

  static SecureStorage get _instance => GetIt.instance<SecureStorage>();

  /// The app's fingerprint, on the registered [SecureStorage].
  static Fingerprint get fingerprint => _instance._fingerprint;

  /// Wipes the fingerprint and the secrets held in memory, when `GetIt.reset`
  /// lets go of this storage.
  ///
  /// The vault itself keeps them.
  @disposeMethod
  void dispose() {
    _fingerprint._wipe();
    _values.clear();
  }

  /// An entry holding a [String], reading as [defaultValue] until it is set.
  static Secure<String> string_(String key, String defaultValue) => _SecureString(_instance, key, defaultValue);

  /// An entry the package keeps for itself, holding a [String] under [key], which
  /// starts with the prefix reserved for the package.
  ///
  /// Reads as an empty string until it is set. Not for a project, which declares
  /// its entries with [string_] and cannot reach these.
  @internal
  Secure<String> packageString(String key) {
    if (!key.startsWith(_reservedPrefix)) {
      throw ArgumentError.value(key, 'key', 'must start with "$_reservedPrefix", as the package\'s own do');
    }
    return _SecureString.package(this, key, '');
  }

  /// An entry holding bytes, reading as [defaultValue] until it is set.
  static Secure<Uint8List> bytes_(String key, Uint8List defaultValue) => _SecureBytes(_instance, key, defaultValue);

  /// An entry holding an [int], reading as [defaultValue] until it is set.
  static Secure<int> int_(String key, int defaultValue) => _SecureInt(_instance, key, defaultValue);

  /// An entry holding a [bool], reading as [defaultValue] until it is set.
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

  /// Throws an [ArgumentError] if [key] is empty or starts with the prefix
  /// reserved for the package.
  void _requireOwnKey(String key) {
    if (key.isEmpty) throw ArgumentError.value(key, 'key', 'cannot be empty');
    if (key.startsWith(_reservedPrefix)) {
      throw ArgumentError.value(key, 'key', 'starts with "$_reservedPrefix", which is the package\'s own');
    }
  }
}

/// One secret of a [SecureStorage]: read it, change it, or follow it.
///
/// ```dart
/// final token = refreshToken();
/// await refreshToken.set('new-token');
/// refreshToken.stream.listen((token) => ...);
/// ```
///
/// Reading is immediate, with nothing to await. Writing returns a future that
/// completes once the vault has kept the new value: only then does the entry
/// change and whoever follows it get notified. A vault that refuses makes the
/// write throw and leaves the entry as it was.
///
/// Declared through the factories of [SecureStorage], never constructed
/// directly.
sealed class Secure<T> extends Observable<T> {
  /// The storage this entry reads from and writes to.
  final SecureStorage _storage;

  /// The key this entry occupies in the vault.
  final String _key;

  /// What this entry reads as until something is set.
  final T _defaultValue;

  /// The current value and its changes, loaded on first use so that a
  /// subclass's own fields are set by then.
  late final BehaviorSubject<T> _valueSubject = BehaviorSubject<T>.seeded(_fetch());

  Secure._(this._storage, this._key, this._defaultValue) {
    _storage._requireOwnKey(_key);
  }

  /// An entry the package keeps for itself, under a key that is reserved.
  Secure._package(this._storage, this._key, this._defaultValue);

  /// The key this entry occupies in the vault.
  String get key => _key;

  @override
  T get value => _valueSubject.value;

  /// The current value, same as [value], so that `token()` reads as well as
  /// `token.value`.
  T call() => _valueSubject.value;

  /// The current value for each new listener, followed by every change.
  @override
  Stream<T> get stream => _valueSubject.stream;

  /// The current value followed by every change, same as [stream].
  @override
  Stream<T> get values => stream;

  /// The value the vault holds for this entry, or the default when it holds
  /// nothing or what it holds no longer decodes.
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

  /// The text the vault keeps for [value].
  String _encode(T value);

  /// Whether [a] and [b] are the same value, which spares a write to the vault.
  bool _same(T a, T b) => a == b;

  /// Keeps [next] in the vault and, only once it has, makes it the value and
  /// notifies whoever follows this entry.
  ///
  /// Throws if the vault refuses, and the entry is left as it was. Setting the
  /// value the entry already has does nothing.
  Future<void> set(T next) async {
    if (_same(next, value)) return;
    await _storage._write(_key, _encode(next));
    if (!_valueSubject.isClosed) _valueSubject.add(next);
  }

  /// Forgets the secret, so that this entry reads as its default again.
  Future<void> clear() async {
    await _storage._write(_key, null);
    if (!_valueSubject.isClosed) _valueSubject.add(_defaultValue);
  }

  /// Closes [stream] for every listener, for an entry that is no longer used.
  Future<void> dispose() => _valueSubject.close();
}

/// The [Secure] behind [SecureStorage.string_].
final class _SecureString extends Secure<String> {
  _SecureString(super.storage, super.key, super.defaultValue) : super._();

  _SecureString.package(super.storage, super.key, super.defaultValue) : super._package();

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
