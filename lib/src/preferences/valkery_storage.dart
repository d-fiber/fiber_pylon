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

/// The default `toJson` for [Valkery.list_]: passes the value through as is.
Object? _identityJson(Object? value) => value;

/// A project's own local preferences, read and written straight through
/// `shared_preferences`'s native types.
///
/// A project declares one entry per setting by extending this and adding a
/// [Valkery] field for each, through whichever of its factories matches the
/// stored type — [Valkery.int_], [Valkery.bool_], [Valkery.double_],
/// [Valkery.string_], [Valkery.array_], [Valkery.enum_] or [Valkery.json_]:
///
/// ```dart
/// class AppPreferences extends ValkeryStorage {
///   late final themeMode = Valkery.enum_(
///     this,
///     'theme_mode',
///     ThemeMode.values,
///     ThemeMode.system,
///   );
///   late final vibrations = Valkery.bool_(this, 'vibrations', true);
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
/// final appPreferences = AppPreferences();
///
/// class MySdkBackend extends Sdk {
///   @override
///   AppPreferences get preferences => appPreferences;
/// }
///
/// // Anywhere else, once sdk.initialize() has run:
/// final theme = appPreferences.themeMode.value;
/// ```
///
/// Pylon keeps no registry of its own to hand [ValkeryStorage] back with: the
/// project already holds the reference it built (`appPreferences` above), so
/// it reuses that instead of asking pylon for one back.
///
/// A backend that keeps a credential through `StoredCredential` can rely on
/// this already being resolved by the time its own override reaches
/// `super.initialize()`, since `Sdk` resolves it first. Only `Sdk` itself
/// declares `preferences`: `SdkClient` and its own `RestSdkClient`,
/// `LocalSdkClient` and `VendorSdkClient` manage their own bootstrap, or
/// need none, instead.
///
/// Every field is declared `late`, so none of them read [prefs] before
/// [initialize] has resolved it.
class ValkeryStorage {
  static final Singleton<ValkeryStorage> _handle = Singleton<ValkeryStorage>('ValkeryStorage');

  late final SharedPreferences _prefs;

  /// Resolves [service]'s underlying `shared_preferences` store and hands it
  /// back ready to use.
  ///
  /// Called by `Sdk.initialize`, never directly by a project: that call
  /// already guards against calling this a second time. Throws a
  /// [StateError] if called again before [dispose].
  static Future<T> initialize<T extends ValkeryStorage>(T service) async {
    service._prefs = await SharedPreferences.getInstance();
    _handle.initialize(service);
    return service;
  }

  /// Whether [initialize] has run.
  static bool get isInitialized => _handle.isInitialized;

  /// Forgets that [initialize] ran, so it can run again.
  ///
  /// Called by `Sdk.dispose`, and by a test between cases. Does not close
  /// any [Valkery] the previous instance handed out; the caller
  /// that created it does.
  static void dispose() => _handle.dispose();

  /// The resolved store this service's own preference fields read and write.
  SharedPreferences get prefs => _prefs;
}

/// One entry of a [ValkeryStorage], read and written in whichever native
/// type `shared_preferences` already stores it as.
///
/// Never constructed directly: [int_], [bool_], [double_], [string_],
/// [array_], [list_], [enum_] and [json_] are the only ways to declare one,
/// each fixing which shape it reads and writes so a project never has to
/// name (or get wrong) the private class actually backing it.
sealed class Valkery<T> extends Observable<T> {
  final ValkeryStorage _service;
  final String _key;
  final T _defaultValue;
  final StreamController<T> _controller = StreamController<T>.broadcast();

  Valkery._(this._service, this._key, this._defaultValue);

  /// An entry holding an [int].
  static Valkery<int> int_(ValkeryStorage service, String key, int defaultValue) =>
      _ValkeryPrimitive<int>(service, key, defaultValue);

  /// An entry holding a [bool].
  static Valkery<bool> bool_(ValkeryStorage service, String key, bool defaultValue) =>
      _ValkeryPrimitive<bool>(service, key, defaultValue);

  /// An entry holding a [double].
  static Valkery<double> double_(ValkeryStorage service, String key, double defaultValue) =>
      _ValkeryPrimitive<double>(service, key, defaultValue);

  /// An entry holding a [String].
  static Valkery<String> string_(ValkeryStorage service, String key, String defaultValue) =>
      _ValkeryPrimitive<String>(service, key, defaultValue);

  /// An entry holding a list of [String], through `shared_preferences`'s own
  /// string list — the only list shape it stores natively.
  static Valkery<List<String>> array_(ValkeryStorage service, String key, List<String> defaultValue) =>
      _ValkeryPrimitive<List<String>>(service, key, defaultValue);

  /// An entry holding a list of [L], JSON-encoded as a whole.
  ///
  /// `shared_preferences` has no native list type beyond [array_]'s own
  /// [String] one, so a list of anything else is JSON-encoded under one key
  /// instead, the same way [json_] encodes a single value. [toJson] defaults
  /// to passing each element through as is, which is enough when [L] is
  /// already one of `jsonEncode`'s own native types; give it explicitly for
  /// anything else, such as a [ValkeryJson].
  ///
  /// A stored value that no longer decodes is reported and answered with
  /// [defaultValue], never thrown, since this is read during startup.
  static Valkery<List<L>> list_<L>(
    ValkeryStorage service,
    String key,
    List<L> defaultValue,
    L Function(dynamic json) fromJson, {
    Object? Function(L value) toJson = _identityJson,
    Reporter reporter = const SilentReporter(),
  }) => _ValkeryJsonList<L>(service, key, defaultValue, fromJson, toJson, reporter: reporter);

  /// An entry holding one member of [E], stored by name rather than by
  /// index, so reordering the enum does not silently change what every
  /// existing installation reads back.
  static Valkery<E> enum_<E extends Enum>(ValkeryStorage service, String key, List<E> values, E defaultValue) =>
      _ValkeryEnum<E>(service, key, values, defaultValue);

  /// An entry holding one [J], JSON-encoded.
  ///
  /// A stored value that no longer decodes is reported and answered with
  /// [defaultValue], never thrown, since this is read during startup.
  static Valkery<J> json_<J extends ValkeryJson?>(
    ValkeryStorage service,
    String key,
    J defaultValue,
    J Function(Map<String, dynamic> json) fromJson, {
    Reporter reporter = const SilentReporter(),
  }) => _ValkeryJsonClass<J>(service, key, defaultValue, fromJson, reporter: reporter);

  /// The key this entry occupies in `shared_preferences`.
  String get key => _key;

  /// What answers a key nothing has written to yet.
  T get defaultValue => _defaultValue;

  @override
  Stream<T> get stream => _controller.stream;

  /// Stores [next] and publishes it on [stream].
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
      case final ValkeryJson v:
        await prefs.setString(_key, jsonEncode(v.toJson()));
      default:
        throw ArgumentError.value(next, 'next', 'not a storable type');
    }

    if (!_controller.isClosed) _controller.add(next);
  }

  /// Removes the stored value and publishes [defaultValue] on [stream].
  Future<void> clear() => set(_defaultValue);

  /// Closes [stream] for every listener.
  Future<void> dispose() => _controller.close();
}

/// The [Valkery] behind [Valkery.int_], [Valkery.bool_], [Valkery.double_],
/// [Valkery.string_] and [Valkery.array_]: whichever native type
/// `shared_preferences` already stores [T] as, read back as is.
final class _ValkeryPrimitive<T> extends Valkery<T> {
  _ValkeryPrimitive(super.service, super.key, super.defaultValue) : super._();

  @override
  T get value {
    final stored = _service.prefs.get(_key);
    if (stored is List<Object?>) {
      final strings = stored.whereType<String>().toList();
      return strings is T ? strings as T : _defaultValue;
    }
    return stored is T ? stored : _defaultValue;
  }
}

/// The [Valkery] behind [Valkery.enum_].
final class _ValkeryEnum<T extends Enum> extends Valkery<T> {
  final List<T> _values;

  _ValkeryEnum(ValkeryStorage service, String key, this._values, T defaultValue) : super._(service, key, defaultValue);

  @override
  T get value {
    final stored = _service.prefs.getString(_key);
    return _values.asNameMap()[stored] ?? defaultValue;
  }
}

/// The [Valkery] behind [Valkery.json_].
final class _ValkeryJsonClass<T extends ValkeryJson?> extends Valkery<T> {
  final T Function(Map<String, dynamic> json) _fromJson;
  final Reporter _reporter;

  _ValkeryJsonClass(
    super.service,
    super.key,
    super.defaultValue,
    this._fromJson, {
    Reporter reporter = const SilentReporter(),
  }) : _reporter = reporter,
       super._();

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

/// The [Valkery] behind [Valkery.list_].
///
/// Stores the whole list as one JSON-encoded string, since
/// `shared_preferences` has no native list type beyond [String]: [set]
/// therefore never reaches [Valkery.set]'s own switch, which would refuse
/// anything but a `List<String>`.
final class _ValkeryJsonList<T> extends Valkery<List<T>> {
  final T Function(dynamic json) _fromJson;
  final Object? Function(T value) _toJson;
  final Reporter _reporter;

  _ValkeryJsonList(
    super.service,
    super.key,
    super.defaultValue,
    this._fromJson,
    this._toJson, {
    Reporter reporter = const SilentReporter(),
  }) : _reporter = reporter,
       super._();

  @override
  List<T> get value {
    final stored = _service.prefs.getString(_key);
    if (stored == null) return defaultValue;
    try {
      return (jsonDecode(stored) as List<dynamic>).map(_fromJson).toList();
    } catch (error, stackTrace) {
      _reporter.recordError(error, stackTrace, context: {'preference': key});
      return defaultValue;
    }
  }

  @override
  Future<void> set(List<T> next) async {
    await _service.prefs.setString(_key, jsonEncode(next.map(_toJson).toList()));
    if (!_controller.isClosed) _controller.add(next);
  }
}

/// A value [Valkery.json_] can store, JSON-encoded.
abstract class ValkeryJson {
  /// This value as JSON, in the shape a project's own `fromJson` rebuilds
  /// from.
  Map<String, dynamic> toJson();
}
