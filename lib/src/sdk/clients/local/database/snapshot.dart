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

/// One document as it was when it was read.
class DocumentSnapshot<T extends Model> {
  DocumentSnapshot._(
    this.reference, {
    String? raw,
    Map<String, Object?>? json,
    T? data,
    this.tenant,
    this.createTime,
    this.updateTime,
  }) : _raw = raw,
       _json = json,
       _data = data;

  /// The document this was read from.
  final DocumentReference<T> reference;

  /// The tenant this document belongs to, or `null` for the anonymous
  /// documents, for a shared collection's, and for a document that does not
  /// exist. What tells apart the copies of one id [Query.acrossTenants]
  /// brings back.
  final String? tenant;

  /// When the document was first written, or `null` when it does not exist.
  final DateTime? createTime;

  /// When the document was last written, or `null` when it does not exist.
  final DateTime? updateTime;

  final String? _raw;
  final Map<String, Object?>? _json;
  final T? _data;

  /// The document's key in its [Collection].
  String get id => reference.id;

  /// Whether the document exists.
  bool get exists => _json != null;

  /// The document as a [T], or `null` when it does not exist.
  T? data() => _data;

  /// The value of [field], read out of the stored JSON as the [V] it is
  /// declared to hold, or `null` when the document or the field is missing.
  ///
  /// A [DateTime] is read back from its stored text, and a [double] from a
  /// number written as a whole one. Throws a [StateError] when what is stored
  /// is not a [V]: the field's declaration and the data disagree.
  V? get<V extends Object>(Field<V> field) {
    final stored = _valueAt(field);
    if (stored == null) return null;
    if (stored is V) return stored;
    if (V == double && stored is int) return stored.toDouble() as V;
    if (V == DateTime && stored is String) {
      return (DateTime.tryParse(stored) ?? _mismatch(field, stored)) as V;
    }
    return _mismatch(field, stored);
  }

  /// The elements of [field], read out of the stored JSON, or `null` when the
  /// document or the field is missing.
  ///
  /// Throws a [StateError] when what is stored is not a list of [E].
  List<E>? getList<E extends Object>(ListField<E> field) {
    final stored = _valueAt(field);
    if (stored == null) return null;
    if (stored is List && stored.every((element) => element is E)) return stored.cast<E>();
    return _mismatch(field, stored);
  }

  Never _mismatch(FieldReference field, Object stored) => throw StateError(
    '${field.name} of ${reference.id} holds $stored (${stored.runtimeType}), which does not fit $field',
  );

  /// The raw stored value at [field], or `null` when there is none.
  Object? _valueAt(FieldReference field) {
    if (_isDocumentId(field)) return id;
    Object? current = _json;
    for (final segment in _segmentsOf(field)) {
      if (current is! Map<String, Object?>) return null;
      current = current[segment];
    }
    return current;
  }
}

/// A [DocumentSnapshot] a [QuerySnapshot] holds: it exists by definition, so
/// [data] never answers `null`.
class QueryDocumentSnapshot<T extends Model> extends DocumentSnapshot<T> {
  QueryDocumentSnapshot._(
    super.reference, {
    super.raw,
    super.json,
    super.data,
    super.tenant,
    super.createTime,
    super.updateTime,
  }) : super._();

  @override
  T data() => _data as T;
}

/// What a [Query] matched, at the moment it ran.
final class QuerySnapshot<T extends Model> {
  QuerySnapshot._(this.docs, this.docChanges);

  /// The matching documents, in the query's own order.
  final List<QueryDocumentSnapshot<T>> docs;

  /// What changed since the previous snapshot of the same [Query.snapshots]
  /// stream — every document as added on the first one.
  final List<DocumentChange<T>> docChanges;

  /// How many documents matched.
  int get size => docs.length;

  /// Whether nothing matched.
  bool get isEmpty => docs.isEmpty;

  /// The matching documents as [T]s.
  List<T> get items => [for (final doc in docs) doc.data()];
}

/// How a document differs between two snapshots of the same query.
enum DocumentChangeType {
  /// The document now matches and did not before.
  added,

  /// The document still matches, with other content or another position.
  modified,

  /// The document no longer matches.
  removed,
}

/// One document that differs between two snapshots of the same query.
final class DocumentChange<T extends Model> {
  DocumentChange._(this.type, this.doc, this.oldIndex, this.newIndex);

  /// How the document changed.
  final DocumentChangeType type;

  /// The document, as of the newer snapshot — or the older one for a removal.
  final QueryDocumentSnapshot<T> doc;

  /// The document's position in the older snapshot, or `-1` for an addition.
  final int oldIndex;

  /// The document's position in the newer snapshot, or `-1` for a removal.
  final int newIndex;
}

List<DocumentChange<T>> _diff<T extends Model>(
  List<QueryDocumentSnapshot<T>>? before,
  List<QueryDocumentSnapshot<T>> after,
) {
  if (before == null) {
    return [for (var i = 0; i < after.length; i++) DocumentChange._(DocumentChangeType.added, after[i], -1, i)];
  }

  (String, String) keyOf(QueryDocumentSnapshot<T> doc) => (doc.tenant ?? '', doc.id);
  final oldIndex = {for (var i = 0; i < before.length; i++) keyOf(before[i]): i};
  final newIds = {for (final doc in after) keyOf(doc)};

  // A document that merely shifted because another one appeared or went away
  // has not moved: among the documents both lists hold, the largest group
  // that kept its relative order is left alone, and only the rest — the ones
  // that jumped over them — are reported as moved.
  final kept = [
    for (var i = 0; i < after.length; i++)
      if (oldIndex.containsKey(keyOf(after[i]))) i,
  ];
  final stable = _longestIncreasing([for (final i in kept) oldIndex[keyOf(after[i])]!]).map((k) => kept[k]).toSet();

  final changes = <DocumentChange<T>>[];
  for (var i = 0; i < before.length; i++) {
    if (!newIds.contains(keyOf(before[i]))) {
      changes.add(DocumentChange._(DocumentChangeType.removed, before[i], i, -1));
    }
  }
  for (var i = 0; i < after.length; i++) {
    final doc = after[i];
    final old = oldIndex[keyOf(doc)];
    if (old == null) {
      changes.add(DocumentChange._(DocumentChangeType.added, doc, -1, i));
    } else if (before[old]._raw != doc._raw || !stable.contains(i)) {
      changes.add(DocumentChange._(DocumentChangeType.modified, doc, old, i));
    }
  }
  return changes;
}

/// The positions in [sequence] of one longest strictly increasing subsequence.
List<int> _longestIncreasing(List<int> sequence) {
  final tails = <int>[]; // tails[k]: position of the smallest tail of an increasing run of length k + 1
  final previous = List.filled(sequence.length, -1);
  for (var i = 0; i < sequence.length; i++) {
    var low = 0;
    var high = tails.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (sequence[tails[mid]] < sequence[i]) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    if (low > 0) previous[i] = tails[low - 1];
    if (low == tails.length) {
      tails.add(i);
    } else {
      tails[low] = i;
    }
  }
  final run = <int>[];
  for (var i = tails.isEmpty ? -1 : tails.last; i != -1; i = previous[i]) {
    run.add(i);
  }
  return run.reversed.toList();
}
