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

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../common/observable.dart';
import '../common/reporter.dart';
import '../common/singleton.dart';

/// A project's own local preferences, read and written straight through
/// `shared_preferences`'s native types.
///
/// A project declares one entry per setting by extending this and adding a
/// [LocalPreference], [LocalPreferenceEnum] or [LocalPreferenceJsonClass]
/// field for each:
///
/// ```dart
/// class AppPreferences extends ValkeryStorage {
///   late final themeMode = LocalPreferenceEnum(
///     this,
///     'theme_mode',
///     ThemeMode.values,
///     ThemeMode.system,
///   );
///   late final vibrations = LocalPreference(this, 'vibrations', true);
/// }
/// ```
///
/// [initialize] is never called by a project directly. A backend overrides
/// `Sdk.preferences` to answer one of these, and `Sdk.initialize` resolves
/// it before anything else runs — once for the whole app, however many
/// implementations ask for it, and however many times one of them is
/// initialized again over the app's life:
///
/// ```dart
/// class MySdkBackend extends Sdk {
///   @override
///   AppPreferences get preferences => AppPreferences();
/// }
///
/// // Anywhere else, once sdk.initialize() has run:
/// final theme = (ValkeryStorage.I as AppPreferences).themeMode.value;
/// ```
///
/// A backend that keeps a credential through `StoredCredential` can rely on
/// this already being resolved by the time its own override reaches
/// `super.initialize()`, since `Sdk` resolves it first. Only `Sdk` itself
/// declares `preferences`: `BackendSdk` and its own `RestBackendSdk`,
/// `LocalBackendSdk` and `VendorBackendSdk` answer to `SdkContract`
/// instead, and manage their own bootstrap, or need none.
///
/// Every field is declared `late`, so none of them read [prefs] before
/// [initialize] has resolved it.
class ValkeryStorage {
  static final Singleton<ValkeryStorage> _handle =
      Singleton<ValkeryStorage>('ValkeryStorage');

  late final SharedPreferences _prefs;

  /// Resolves [service]'s underlying `shared_preferences` store, registers it
  /// as [I], and hands it back ready to use.
  ///
  /// Called by `Sdk.initialize`, never directly by a project: that call
  /// already guards against calling this a second time. Throws a
  /// [StateError] if called again before [dispose].
  static Future<T> initialize<T extends ValkeryStorage>(T service) async {
    service._prefs = await SharedPreferences.getInstance();
    _handle.initialize(service);
    return service;
  }

  /// The instance [initialize] registered.
  ///
  /// Throws a [StateError] if [initialize] has not run yet.
  static ValkeryStorage get I => _handle.instance;

  /// Whether [initialize] has run.
  static bool get isInitialized => _handle.isInitialized;

  /// Forgets the registered instance, so [initialize] can register another.
  ///
  /// Called by `Sdk.dispose`, and by a test between cases. Does not close
  /// any [LocalPreference] the previous instance handed out; the caller
  /// that created it does.
  static void dispose() => _handle.dispose();

  /// The resolved store this service's own preference fields read and write.
  SharedPreferences get prefs => _prefs;
}

/// One entry of a [ValkeryStorage], read and written in whichever native
/// type `shared_preferences` already stores it as.
class LocalPreference<T> extends Observable<T> {
  final ValkeryStorage _service;
  final String _key;
  final T _defaultValue;
  final StreamController<T> _controller = StreamController<T>.broadcast();

  /// Declares the entry [key] on [service], answering [defaultValue] until
  /// something writes to it.
  LocalPreference(this._service, this._key, this._defaultValue);

  /// The key this entry occupies in `shared_preferences`.
  String get key => _key;

  /// What answers a key nothing has written to yet.
  T get defaultValue => _defaultValue;

  @override
  T get value {
    final stored = _service.prefs.get(_key);
    if (stored is List<Object?>) {
      final strings = stored.whereType<String>().toList();
      return strings is T ? strings as T : _defaultValue;
    }
    return stored is T ? stored : _defaultValue;
  }

  @override
  Stream<T> get changes => _controller.stream;

  /// Stores [next] and publishes it on [changes].
  ///
  /// Ignored when [next] already equals [value], except for a [List]: two
  /// lists that compare unequal by identity can still hold the same
  /// elements, and a caller that mutated one in place expects the write to
  /// happen regardless.
  Future<void> set(T next) async {
    if (next is! List && next == value) return;

    final prefs = _service.prefs;
    switch (next) {
      case null:
        await prefs.remove(_key);
      case final bool v:
        await prefs.setBool(_key, v);
      case final int v:
        await prefs.setInt(_key, v);
      case final double v:
        await prefs.setDouble(_key, v);
      case final String v:
        await prefs.setString(_key, v);
      case final List<String> v:
        await prefs.setStringList(_key, v);
      case final Enum v:
        await prefs.setString(_key, v.name);
      case final JsonClass v:
        await prefs.setString(_key, jsonEncode(v.toJson()));
      default:
        throw ArgumentError.value(next, 'next', 'not a storable type');
    }

    if (!_controller.isClosed) _controller.add(next);
  }

  /// Removes the stored value and publishes [defaultValue] on [changes].
  Future<void> clear() => set(_defaultValue);

  /// Closes [changes] for every listener.
  Future<void> dispose() => _controller.close();
}

/// A [LocalPreference] that reads and writes one member of an enum, by name.
///
/// The name is stored rather than the index, so reordering the enum does not
/// silently change what every existing installation reads back.
class LocalPreferenceEnum<T extends Enum> extends LocalPreference<T> {
  final List<T> _values;

  /// Declares the entry [key] on [service], resolving what
  /// `shared_preferences` holds against [values] by name, and answering
  /// [defaultValue] when nothing matches.
  LocalPreferenceEnum(
    ValkeryStorage service,
    String key,
    this._values,
    T defaultValue,
  ) : super(service, key, defaultValue);

  @override
  T get value {
    final stored = _service.prefs.getString(_key);
    return _values.asNameMap()[stored] ?? defaultValue;
  }
}

/// A [LocalPreference] that reads and writes one [JsonClass], JSON-encoded.
///
/// A stored value that no longer decodes is reported and answered with
/// [defaultValue], never thrown, since this is read during startup.
class LocalPreferenceJsonClass<T extends JsonClass?>
    extends LocalPreference<T> {
  final T Function(Map<String, dynamic> json) _fromJson;
  final Reporter _reporter;

  /// Declares the entry [key] on [service], decoding what
  /// `shared_preferences` holds with [fromJson].
  LocalPreferenceJsonClass(
    super.service,
    super.key,
    super.defaultValue,
    this._fromJson, {
    Reporter reporter = const SilentReporter(),
  }) : _reporter = reporter;

  @override
  T get value {
    final stored = _service.prefs.getString(_key);
    if (stored == null) return defaultValue;
    try {
      return _fromJson(jsonDecode(stored) as Map<String, dynamic>);
    } catch (error, stackTrace) {
      _reporter.recordError(error, stackTrace, context: {'preference': key});
      return defaultValue;
    }
  }
}

/// A value a [LocalPreferenceJsonClass] can store, JSON-encoded.
abstract class JsonClass {
  /// This value as JSON, in the shape a project's own `fromJson` rebuilds
  /// from.
  Map<String, dynamic> toJson();
}
