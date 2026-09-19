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

part of 'database.dart';

/// A value that is resolved against what the document already holds, rather
/// than written as it is.
///
/// Valid as a value in [DocumentReference.update] — and, nested at any depth
/// in the map [Model.toJson] answers, in [DocumentReference.set] and
/// [Collection.add]. There it resolves against the stored document when the
/// write merges into it, and against nothing when it replaces or creates one:
/// an [FieldValue.increment] then counts from `0`, an [FieldValue.arrayUnion]
/// starts an empty list, and a [FieldValue.delete] leaves the field out.
sealed class FieldValue {
  const FieldValue._();

  /// The time of the write, taken from this device's own clock, as UTC
  /// ISO-8601 text.
  const factory FieldValue.serverTimestamp() = _ServerTimestamp;

  /// Removes the field.
  const factory FieldValue.delete() = _Delete;

  /// Adds [by] to the number the field holds, treating a missing or
  /// non-numeric field as `0`.
  const factory FieldValue.increment(num by) = _Increment;

  /// Appends each of [elements] the list the field holds does not already
  /// contain.
  factory FieldValue.arrayUnion(List<Object?> elements) => _ArrayUnion(elements);

  /// Removes every occurrence of each of [elements] from the list the field
  /// holds.
  factory FieldValue.arrayRemove(List<Object?> elements) => _ArrayRemove(elements);

  /// What the field holds once this is applied to [current]; [_removed] means
  /// the field goes away.
  Object? _apply(Object? current);
}

const Object _removed = Object();

final class _ServerTimestamp extends FieldValue {
  const _ServerTimestamp() : super._();

  @override
  Object? _apply(Object? current) => DateTime.now().toUtc().toIso8601String();
}

final class _Delete extends FieldValue {
  const _Delete() : super._();

  @override
  Object? _apply(Object? current) => _removed;
}

final class _Increment extends FieldValue {
  const _Increment(this.by) : super._();

  final num by;

  @override
  Object? _apply(Object? current) => (current is num ? current : 0) + by;
}

final class _ArrayUnion extends FieldValue {
  _ArrayUnion(List<Object?> elements) : elements = _normalizeAll(elements), super._();

  final List<Object?> elements;

  @override
  Object? _apply(Object? current) {
    final list = current is List ? [...current] : <Object?>[];
    for (final element in elements) {
      if (!list.any((held) => _jsonEquals(held, element))) list.add(element);
    }
    return list;
  }
}

final class _ArrayRemove extends FieldValue {
  _ArrayRemove(List<Object?> elements) : elements = _normalizeAll(elements), super._();

  final List<Object?> elements;

  @override
  Object? _apply(Object? current) {
    if (current is! List) return <Object?>[];
    return [
      for (final held in current)
        if (!elements.any((element) => _jsonEquals(held, element))) held,
    ];
  }
}

List<Object?> _normalizeAll(List<Object?> values) => [for (final value in values) _normalize(value)];

bool _jsonEquals(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

/// Turns [value] into exactly what JSON stores for it, so what a write holds
/// and what a later read decodes are the same thing.
Object? _normalize(Object? value) {
  try {
    return jsonDecode(jsonEncode(value, toEncodable: _toEncodable));
  } on JsonUnsupportedObjectError catch (error) {
    throw ArgumentError.value(error.unsupportedObject, 'value', 'cannot be stored: not a JSON value');
  }
}

Object? _toEncodable(Object? value) {
  if (value is DateTime) return value.toUtc().toIso8601String();
  if (value is Enum) return value.name;
  if (value is Model) return value.toJson();
  // ignore: avoid_dynamic_calls
  return (value as dynamic).toJson();
}

/// Applies every one of [changes] to [data], in order: a dotted field name
/// reaches into a nested map, creating the maps on the way, and a
/// [FieldValue] resolves against what the field holds now.
void _applyUpdates(Map<String, Object?> data, List<FieldChange> changes) {
  for (final change in changes) {
    final path = _segmentsOf(change._field);
    var parent = data;
    for (final segment in path.take(path.length - 1)) {
      final next = parent[segment];
      if (next is Map<String, Object?>) {
        parent = next;
      } else {
        parent = parent[segment] = <String, Object?>{};
      }
    }
    final key = path.last;
    final value = change._value;
    final resolved = value is FieldValue ? value._apply(parent[key]) : _normalize(value);
    if (identical(resolved, _removed)) {
      parent.remove(key);
    } else {
      parent[key] = resolved;
    }
  }
}

/// [patch] laid over [base], maps merged key by key all the way down and
/// everything else — a list included — replaced.
Map<String, Object?> _deepMerge(Map<String, Object?> base, Map<String, Object?> patch) {
  final merged = {...base};
  patch.forEach((key, value) {
    final held = merged[key];
    merged[key] = (held is Map<String, Object?> && value is Map<String, Object?>) ? _deepMerge(held, value) : value;
  });
  return merged;
}

/// [fields] with every [FieldValue] in it — at any depth of nested maps —
/// replaced by what it resolves to against [held], the stored fields at the
/// same place, or against nothing when [held] is `null`.
Map<String, Object?> _resolveFieldValues(Map<String, Object?> fields, Map<String, Object?>? held) {
  final resolved = <String, Object?>{};
  fields.forEach((key, value) {
    final current = held?[key];
    if (value is FieldValue) {
      final next = value._apply(current);
      if (!identical(next, _removed)) resolved[key] = next;
    } else if (value is Map<String, Object?>) {
      resolved[key] = _resolveFieldValues(value, current is Map<String, Object?> ? current : null);
    } else {
      resolved[key] = value;
    }
  });
  return resolved;
}
