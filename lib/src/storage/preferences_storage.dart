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

import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../common/observable.dart';
import '../common/reporter.dart';

/// The default `toJson` of [Preference.list_], which returns [value] unchanged.
Object? _identityJson(Object? value) => value;

/// The app's local settings, which survive a restart.
///
/// A project declares one entry per setting, with the factory that matches its
/// type: [int_], [bool_], [double_], [string_], [list_], [enum_] or [json_].
/// There is no storage object to hold or pass around, the factories find it on
/// their own:
///
/// ```dart
/// class AppPreferences {
///   late final themeMode = PreferencesStorage.enum_('theme_mode', ThemeMode.values, ThemeMode.system);
///   late final vibrations = PreferencesStorage.bool_('vibrations', true);
/// }
/// ```
///
/// Each entry is then read with `vibrations()` and written with
/// `await vibrations.set(false)`, see [Preference].
///
/// Declare entries only once `configureSdk` has run, since that is what makes
/// the storage available.
@Singleton(order: -1)
class PreferencesStorage {
  /// The `shared_preferences` instance every entry reads from and writes to.
  late final SharedPreferences _prefs;

  /// Prepares the storage for `configureSdk`.
  ///
  /// Called by `configureSdk`, never by a project.
  @FactoryMethod(preResolve: true)
  static Future<PreferencesStorage> initialize() async {
    final service = PreferencesStorage();
    service._prefs = await SharedPreferences.getInstance();
    return service;
  }

  static PreferencesStorage get _instance => GetIt.instance<PreferencesStorage>();

  /// An entry holding an [int], reading as [defaultValue] until it is set.
  static Preference<int> int_(String key, int defaultValue) => Preference.int_(_instance, key, defaultValue);

  /// An entry holding a [bool], reading as [defaultValue] until it is set.
  static Preference<bool> bool_(String key, bool defaultValue) => Preference.bool_(_instance, key, defaultValue);

  /// An entry holding a [double], reading as [defaultValue] until it is set.
  static Preference<double> double_(String key, double defaultValue) =>
      Preference.double_(_instance, key, defaultValue);

  /// An entry holding a [String], reading as [defaultValue] until it is set.
  static Preference<String> string_(String key, String defaultValue) =>
      Preference.string_(_instance, key, defaultValue);

  /// An entry holding a list of [L], reading as [defaultValue] until it is set.
  ///
  /// [fromJson] builds one element back when the list is read. [toJson] turns
  /// one element into something that can be saved, and is only needed when [L]
  /// is not a basic type such as [int] or [String].
  ///
  /// When the saved list can no longer be read, [reporter] is told and the entry
  /// reads as [defaultValue].
  static Preference<List<L>> list_<L>(
    String key,
    List<L> defaultValue,
    L Function(dynamic json) fromJson, {
    Object? Function(L value) toJson = _identityJson,
    Reporter reporter = const SilentReporter(),
  }) => Preference.list_<L>(_instance, key, defaultValue, fromJson, toJson: toJson, reporter: reporter);

  /// An entry holding one member of [values], reading as [defaultValue] until it
  /// is set.
  ///
  /// Members can be reordered without affecting what is already saved. A saved
  /// member that has been removed from the enum reads as [defaultValue].
  static Preference<E> enum_<E extends Enum>(String key, List<E> values, E defaultValue) =>
      Preference.enum_(_instance, key, values, defaultValue);

  /// An entry holding one [J], reading as [defaultValue] until it is set.
  ///
  /// [fromJson] builds the value back when it is read.
  ///
  /// When the saved value can no longer be read, [reporter] is told and the
  /// entry reads as [defaultValue].
  static Preference<J> json_<J extends PreferenceJson?>(
    String key,
    J defaultValue,
    J Function(Map<String, dynamic> json) fromJson, {
    Reporter reporter = const SilentReporter(),
  }) => Preference.json_<J>(_instance, key, defaultValue, fromJson, reporter: reporter);
}

/// One setting of a [PreferencesStorage]: read it, change it, or follow it.
///
/// ```dart
/// final enabled = vibrations();
/// await vibrations.set(false);
/// vibrations.stream.listen((enabled) => ...);
/// ```
///
/// Reading is immediate, with nothing to await. Writing returns a future that
/// completes once the new value is saved, and whoever follows the entry is then
/// notified.
///
/// Declared through the factories of [PreferencesStorage], never constructed
/// directly.
sealed class Preference<T> extends Observable<T> {
  /// The storage this entry reads from and writes to.
  final PreferencesStorage _preferences;

  /// Backs [key].
  final String _key;

  /// Backs [defaultValue].
  final T _defaultValue;

  /// The current value and its changes, loaded on first use so that a
  /// subclass's own fields are set by then.
  late final BehaviorSubject<T> _valueSubject = BehaviorSubject<T>.seeded(_fetch());

  Preference._(this._preferences, this._key, this._defaultValue);

  /// Same as [PreferencesStorage.int_], on [service].
  static Preference<int> int_(PreferencesStorage service, String key, int defaultValue) =>
      _PreferencePrimitive<int>(service, key, defaultValue);

  /// Same as [PreferencesStorage.bool_], on [service].
  static Preference<bool> bool_(PreferencesStorage service, String key, bool defaultValue) =>
      _PreferencePrimitive<bool>(service, key, defaultValue);

  /// Same as [PreferencesStorage.double_], on [service].
  static Preference<double> double_(PreferencesStorage service, String key, double defaultValue) =>
      _PreferencePrimitive<double>(service, key, defaultValue);

  /// Same as [PreferencesStorage.string_], on [service].
  static Preference<String> string_(PreferencesStorage service, String key, String defaultValue) =>
      _PreferencePrimitive<String>(service, key, defaultValue);

  /// Same as [PreferencesStorage.list_], on [service].
  static Preference<List<L>> list_<L>(
    PreferencesStorage service,
    String key,
    List<L> defaultValue,
    L Function(dynamic json) fromJson, {
    Object? Function(L value) toJson = _identityJson,
    Reporter reporter = const SilentReporter(),
  }) => _PreferenceJsonList<L>(service, key, defaultValue, fromJson, toJson, reporter: reporter);

  /// Same as [PreferencesStorage.enum_], on [service].
  static Preference<E> enum_<E extends Enum>(PreferencesStorage service, String key, List<E> values, E defaultValue) =>
      _PreferenceEnum<E>(service, key, values, defaultValue);

  /// Same as [PreferencesStorage.json_], on [service].
  static Preference<J> json_<J extends PreferenceJson?>(
    PreferencesStorage service,
    String key,
    J defaultValue,
    J Function(Map<String, dynamic> json) fromJson, {
    Reporter reporter = const SilentReporter(),
  }) => _PreferenceJsonClass<J>(service, key, defaultValue, fromJson, reporter: reporter);

  /// The key this entry is saved under.
  String get key => _key;

  /// What this entry reads as until something is set.
  T get defaultValue => _defaultValue;

  @override
  T get value => _valueSubject.value;

  /// The current value, same as [value], so that `vibrations()` reads as well as
  /// `vibrations.value`.
  T call() => _valueSubject.value;

  /// The current value for each new listener, followed by every change.
  @override
  Stream<T> get stream => _valueSubject.stream;

  /// The current value followed by every change, same as [stream].
  @override
  Stream<T> get values => stream;

  /// The saved value, or [defaultValue] when there is none that can be read.
  T _fetch();

  /// Saves [next] and notifies whoever follows this entry.
  ///
  /// Setting the value the entry already has does nothing, except for a list,
  /// which is always saved so that it can be changed in place and set again.
  ///
  /// Throws an [ArgumentError] if [next] is not a type that can be saved.
  Future<void> set(T next) async {
    if (next is! List && next == value) return;

    final prefs = _preferences._prefs;
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
      case final PreferenceJson v:
        await prefs.setString(_key, jsonEncode(v.toJson()));
      default:
        throw ArgumentError.value(next, 'next', 'not a storable type');
    }

    if (!_valueSubject.isClosed) _valueSubject.add(next);
  }

  /// Resets this entry to [defaultValue] and publishes it on [stream].
  Future<void> clear() => set(_defaultValue);

  /// Closes [stream] for every listener, for an entry that is no longer used.
  Future<void> dispose() => _valueSubject.close();
}

/// The [Preference] behind [Preference.int_], [Preference.bool_],
/// [Preference.double_] and [Preference.string_].
final class _PreferencePrimitive<T> extends Preference<T> {
  _PreferencePrimitive(super.service, super.key, super.defaultValue) : super._();

  @override
  T _fetch() {
    final savedValue = _preferences._prefs.get(key);
    if (savedValue is List<Object?>) {
      final strings = savedValue.whereType<String>().toList();
      return strings is T ? strings as T : defaultValue;
    }
    return savedValue is T ? savedValue : defaultValue;
  }
}

/// The [Preference] behind [Preference.enum_].
final class _PreferenceEnum<T extends Enum> extends Preference<T> {
  final List<T> _values;

  _PreferenceEnum(PreferencesStorage service, String key, this._values, T defaultValue)
    : super._(service, key, defaultValue);

  @override
  T _fetch() {
    final stored = _preferences._prefs.getString(key);
    return _values.asNameMap()[stored] ?? defaultValue;
  }
}

/// The [Preference] behind [Preference.json_].
final class _PreferenceJsonClass<T extends PreferenceJson?> extends Preference<T> {
  final T Function(Map<String, dynamic> json) _fromJson;
  final Reporter _reporter;

  _PreferenceJsonClass(
    super.service,
    super.key,
    super.defaultValue,
    this._fromJson, {
    Reporter reporter = const SilentReporter(),
  }) : _reporter = reporter,
       super._();

  @override
  T _fetch() {
    final stored = _preferences._prefs.getString(key);
    if (stored == null) return defaultValue;
    try {
      return _fromJson(jsonDecode(stored) as Map<String, dynamic>);
    } catch (error, stackTrace) {
      _reporter.recordError(error, stackTrace, context: {'preference': key});
      return defaultValue;
    }
  }
}

/// The [Preference] behind [Preference.list_].
final class _PreferenceJsonList<T> extends Preference<List<T>> {
  final T Function(dynamic json) _fromJson;
  final Object? Function(T value) _toJson;
  final Reporter _reporter;

  _PreferenceJsonList(
    super.service,
    super.key,
    super.defaultValue,
    this._fromJson,
    this._toJson, {
    Reporter reporter = const SilentReporter(),
  }) : _reporter = reporter,
       super._();

  @override
  List<T> _fetch() {
    final stored = _preferences._prefs.getString(key);
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
    await _preferences._prefs.setString(key, jsonEncode(next.map(_toJson).toList()));
    if (!_valueSubject.isClosed) _valueSubject.add(next);
  }
}

/// A class whose instances a [Preference.json_] entry can save.
abstract class PreferenceJson {
  /// This value as a JSON map, which the entry's `fromJson` turns back into a
  /// value.
  Map<String, dynamic> toJson();
}
