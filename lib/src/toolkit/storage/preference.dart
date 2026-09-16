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

import '../observable.dart';
import '../reporter.dart';
import 'key_value_store.dart';

/// One typed, watchable entry of a [KeyValueStore].
///
/// A project declares its preferences once and holds on to them, because
/// [changes] belongs to the instance: rebuilding a preference on every access
/// hands out a stream nobody ever publishes on.
///
/// A value written to the underlying store by something other than this
/// preference is visible on the next read of [value] but does not publish on
/// [changes]. Nothing here watches the store; a store shared between writers
/// needs them to agree on who owns which key.
///
/// A stored value that no longer decodes is reported and answered with
/// [fallback], never thrown. Preferences are read during startup, and a shape
/// that changed between two versions of an app must not be able to prevent it
/// from opening.
class Preference<T> extends Observable<T> {
  final KeyValueStore _store;
  final String _key;
  final T _fallback;
  final String Function(T value) _encode;
  final T Function(String raw) _decode;
  final Reporter _reporter;
  final StreamController<T> _controller = StreamController<T>.broadcast();

  /// Declares the entry stored under [key], decoded with [decode] and written
  /// back with [encode].
  ///
  /// [fallback] answers a key that was never written, and a stored value that
  /// fails to decode.
  Preference({
    required KeyValueStore store,
    required String key,
    required T fallback,
    required String Function(T value) encode,
    required T Function(String raw) decode,
    Reporter reporter = const SilentReporter(),
  }) : _store = store,
       _key = key,
       _fallback = fallback,
       _encode = encode,
       _decode = decode,
       _reporter = reporter;

  /// Declares a string entry.
  static Preference<String> text({
    required KeyValueStore store,
    required String key,
    String fallback = '',
    Reporter reporter = const SilentReporter(),
  }) => Preference<String>(
    store: store,
    key: key,
    fallback: fallback,
    encode: _identity,
    decode: _identity,
    reporter: reporter,
  );

  /// Declares an integer entry.
  static Preference<int> integer({
    required KeyValueStore store,
    required String key,
    int fallback = 0,
    Reporter reporter = const SilentReporter(),
  }) => Preference<int>(
    store: store,
    key: key,
    fallback: fallback,
    encode: _encodeInt,
    decode: int.parse,
    reporter: reporter,
  );

  /// Declares a boolean entry.
  static Preference<bool> flag({
    required KeyValueStore store,
    required String key,
    bool fallback = false,
    Reporter reporter = const SilentReporter(),
  }) => Preference<bool>(
    store: store,
    key: key,
    fallback: fallback,
    encode: _encodeBool,
    decode: _decodeBool,
    reporter: reporter,
  );

  /// Declares an entry holding one member of [values], stored by its name.
  ///
  /// The name is stored rather than the index, so reordering the enum does not
  /// silently change what every existing installation reads back.
  static Preference<T> enumeration<T extends Enum>({
    required KeyValueStore store,
    required String key,
    required List<T> values,
    required T fallback,
    Reporter reporter = const SilentReporter(),
  }) {
    final byName = values.asNameMap();
    return Preference<T>(
      store: store,
      key: key,
      fallback: fallback,
      encode: (value) => value.name,
      decode: (raw) {
        final member = byName[raw];
        if (member == null) throw FormatException('Unknown member', raw);
        return member;
      },
      reporter: reporter,
    );
  }

  /// The key this preference occupies in the store.
  String get key => _key;

  /// What answers a key that was never written, or one that fails to decode.
  T get fallback => _fallback;

  /// Whether the store currently holds anything under [key].
  bool get isSet => _store.read(_key) != null;

  @override
  T get value {
    final raw = _store.read(_key);
    if (raw == null) return _fallback;
    try {
      return _decode(raw);
    } catch (error, stackTrace) {
      _reporter.recordError(error, stackTrace, context: {'preference': _key});
      return _fallback;
    }
  }

  @override
  Stream<T> get changes => _controller.stream;

  /// Stores [next] and publishes it on [changes].
  Future<void> set(T next) async {
    await _store.write(_key, _encode(next));
    if (!_controller.isClosed) _controller.add(next);
  }

  /// Removes the stored value and publishes [fallback] on [changes].
  Future<void> clear() async {
    await _store.delete(_key);
    if (!_controller.isClosed) _controller.add(_fallback);
  }

  /// Closes [changes] for every listener.
  Future<void> dispose() => _controller.close();
}

String _identity(String value) => value;

String _encodeInt(int value) => '$value';

String _encodeBool(bool value) => value ? 'true' : 'false';

bool _decodeBool(String raw) => switch (raw) {
  'true' => true,
  'false' => false,
  _ => throw FormatException('Not a boolean', raw),
};
