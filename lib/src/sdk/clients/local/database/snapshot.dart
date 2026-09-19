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

/// One document as it was when it was read: the record a row holds, and the key
/// it is held under.
class DocumentSnapshot<R extends Object, K extends Object> {
  DocumentSnapshot._(this.id, this._data);

  /// The document's key in its [Collection].
  final K id;

  final R? _data;

  /// Whether the document exists.
  bool get exists => _data != null;

  /// The record, or `null` when the document does not exist.
  R? data() => _data;
}

/// A [DocumentSnapshot] a [QuerySnapshot] holds: it exists by definition, so
/// [data] never answers `null`.
final class QueryDocumentSnapshot<R extends Object, K extends Object> extends DocumentSnapshot<R, K> {
  QueryDocumentSnapshot._(super.id, R super._data) : super._();

  @override
  R data() => _data as R;
}

/// What a [Query] matched, at the moment it ran.
final class QuerySnapshot<R extends Object, K extends Object> {
  QuerySnapshot._(this.docs, this.docChanges);

  /// The matching documents, in the query's own order.
  final List<QueryDocumentSnapshot<R, K>> docs;

  /// What changed since the previous snapshot of the same [Query.snapshots]
  /// stream — every document as added on the first one, and again on the first
  /// one after [Tenant.use] or [Tenant.leave], since the previous tenant's
  /// documents are never carried over.
  final List<DocumentChange<R, K>> docChanges;

  /// How many documents matched.
  int get size => docs.length;

  /// Whether nothing matched.
  bool get isEmpty => docs.isEmpty;

  /// The matching documents as records.
  List<R> get items => [for (final doc in docs) doc.data()];
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
final class DocumentChange<R extends Object, K extends Object> {
  DocumentChange._(this.type, this.doc, this.oldIndex, this.newIndex);

  /// How the document changed.
  final DocumentChangeType type;

  /// The document, as of the newer snapshot — or the older one for a removal.
  final QueryDocumentSnapshot<R, K> doc;

  /// The document's position in the older snapshot, or `-1` for an addition.
  final int oldIndex;

  /// The document's position in the newer snapshot, or `-1` for a removal.
  final int newIndex;
}

List<QueryDocumentSnapshot<R, K>> _documentsOf<R extends Object, K extends Object>(
  DatabaseKeyedTable<R, K> table,
  List<R> records,
) => [
  for (final record in records)
    QueryDocumentSnapshot<R, K>._(
      table.keyOf(record) ?? (throw StateError('A record read from ${table.tableName} carries no key.')),
      record,
    ),
];

List<DocumentChange<R, K>> _diff<R extends Object, K extends Object>(
  DatabaseKeyedTable<R, K> table,
  List<QueryDocumentSnapshot<R, K>>? before,
  List<QueryDocumentSnapshot<R, K>> after,
) {
  if (before == null) {
    return [for (var i = 0; i < after.length; i++) DocumentChange._(DocumentChangeType.added, after[i], -1, i)];
  }

  final oldIndex = {for (var i = 0; i < before.length; i++) before[i].id: i};
  final newIds = {for (final doc in after) doc.id};

  // A document that merely shifted because another one appeared or went away
  // has not moved: among the documents both lists hold, the largest group that
  // kept its relative order is left alone, and only the rest — the ones that
  // jumped over them — are reported as moved.
  final kept = [
    for (var i = 0; i < after.length; i++)
      if (oldIndex.containsKey(after[i].id)) i,
  ];
  final stable = _longestIncreasing([for (final i in kept) oldIndex[after[i].id]!]).map((k) => kept[k]).toSet();

  final changes = <DocumentChange<R, K>>[];
  for (var i = 0; i < before.length; i++) {
    if (!newIds.contains(before[i].id)) {
      changes.add(DocumentChange._(DocumentChangeType.removed, before[i], i, -1));
    }
  }
  for (var i = 0; i < after.length; i++) {
    final doc = after[i];
    final old = oldIndex[doc.id];
    if (old == null) {
      changes.add(DocumentChange._(DocumentChangeType.added, doc, -1, i));
    } else if (!table.isSameRecord(before[old].data(), doc.data()) || !stable.contains(i)) {
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
