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

/// A document that no longer — or never did — exist, reached by an operation
/// that needs one, such as [DocumentReference.update].
final class DocumentNotFoundError implements Exception {
  /// The document [id] of [collection] that was not found.
  const DocumentNotFoundError(this.collection, this.id);

  /// The collection that was searched.
  final String collection;

  /// The id that was not there.
  final String id;

  @override
  String toString() => 'DocumentNotFoundError(no document "$id" in "$collection")';
}

/// One document of a [Collection], which may or may not exist yet.
///
/// Holds nothing but where the document lives: [get], [set], [update],
/// [delete] and [snapshots] are what actually reach the database.
///
/// On an isolated collection the same id names one document per tenant. Each
/// operation reaches the tenant that is current when it starts — or the one
/// [Collection.inTenant] pinned — and finishes on it even if [Tenant.use] is
/// called meanwhile.
final class DocumentReference<T extends Model> {
  const DocumentReference._(this.parent, this.id);

  /// The collection this document belongs to.
  final Collection<T> parent;

  /// This document's key in [parent].
  final String id;

  /// Which partition of [parent] this reference reaches, resolved now. Every
  /// operation reads it once, synchronously, before it awaits anything, so it
  /// finishes on the tenant that was current when it started.
  String get _tenant => parent._scope.reach(parent).tenant!;

  /// Reads the document, which need not exist: check [DocumentSnapshot.exists].
  Future<DocumentSnapshot<T>> get() async {
    final tenant = _tenant;
    await parent._ensure();
    return _read(const _StorageExecutor(), tenant);
  }

  /// Writes [data] as this document, replacing what it held — or, with
  /// [merge], laying [data]'s fields over it, maps merged all the way down.
  ///
  /// [Model.id] is ignored: the document's key is this reference's own.
  Future<void> set(T data, {bool merge = false}) {
    final tenant = _tenant;
    return _run((executor) => _set(executor, tenant, data, merge));
  }

  /// Changes only the fields [build] names, leaving the rest as they are.
  ///
  /// [build] returns the changes, composed from an [UpdateBuilder] and typed
  /// on what each field holds:
  ///
  /// ```dart
  /// await users.doc('ada').update((u) => [u(User.age_).increment(1), u(User.city_).set('Paris')]);
  /// ```
  ///
  /// Throws a [DocumentNotFoundError] when the document does not exist, and an
  /// [ArgumentError] when [build] returns nothing.
  Future<void> update(List<FieldChange> Function(UpdateBuilder u) build) {
    final tenant = _tenant;
    final changes = _changesOf(build);
    return _run((executor) => _update(executor, tenant, changes));
  }

  /// Removes the document. Removing one that does not exist is not an error.
  Future<void> delete() {
    final tenant = _tenant;
    return _run((executor) => _delete(executor, tenant));
  }

  /// Reads the document now, then again after every write to it, emitting a
  /// [DocumentSnapshot] each time it differs. Nothing runs until the stream is
  /// listened to.
  ///
  /// On an isolated collection it follows [Tenant]: after [Tenant.use] it
  /// emits the new tenant's document, never the previous one's.
  Stream<DocumentSnapshot<T>> snapshots() {
    late final StreamController<DocumentSnapshot<T>> controller;
    StreamSubscription<void>? subscription;
    StreamSubscription<void>? tenantSubscription;
    DocumentSnapshot<T>? previous;
    var running = false;
    var dirty = false;
    var startOver = false;

    Future<void> refresh() async {
      if (running) {
        dirty = true;
        return;
      }
      running = true;
      try {
        do {
          dirty = false;
          final tenant = _tenant;
          final current = await get();
          if (controller.isClosed) return;
          if (tenant != _tenant) {
            // the tenant changed while reading: what came back is not theirs
            startOver = dirty = true;
            continue;
          }
          if (startOver) previous = null;
          startOver = false;
          if (previous == null || previous!._raw != current._raw) {
            controller.add(current);
          }
          previous = current;
        } while (dirty && !controller.isClosed);
      } catch (error, stackTrace) {
        if (!controller.isClosed) controller.addError(error, stackTrace);
      } finally {
        running = false;
      }
    }

    controller = StreamController<DocumentSnapshot<T>>(
      onListen: () {
        subscription = _ChangeBus.changes(parent.name).listen((_) => unawaited(refresh()));
        if (parent._scope is _CurrentScope && parent.tunnel == Tunnel.isolated) {
          tenantSubscription = Tenant.changes.listen((_) {
            startOver = true;
            unawaited(refresh());
          });
        }
        unawaited(refresh());
      },
      onCancel: () async {
        await subscription?.cancel();
        await tenantSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  bool operator ==(Object other) =>
      other is DocumentReference &&
      other.parent.name == parent.name &&
      other.id == id &&
      other.parent._scope == parent._scope;

  @override
  int get hashCode => Object.hash(parent.name, id);

  @override
  String toString() => 'DocumentReference(${parent.name}/$id)';

  /// Prepares the table, runs [write] in one transaction, then tells every
  /// listener on the collection.
  Future<void> _run(Future<void> Function(_Executor executor) write) async {
    await parent._ensure();
    await _atomically(write);
    _ChangeBus.notify(parent.name);
  }

  Future<DocumentSnapshot<T>> _read(_Executor executor, String tenant) async {
    final rows = await executor.rawQuery(
      'SELECT tenant, id, data, created_at, updated_at FROM "${parent.name}" WHERE tenant = ? AND id = ?',
      [DatabaseType.varchar(tenant), DatabaseType.varchar(id)],
    );
    return rows.isEmpty ? DocumentSnapshot._(this) : parent._documentOf(rows.first);
  }

  Future<Map<String, Object?>?> _load(_Executor executor, String tenant) async {
    final rows = await executor.rawQuery('SELECT data FROM "${parent.name}" WHERE tenant = ? AND id = ?', [
      DatabaseType.varchar(tenant),
      DatabaseType.varchar(id),
    ]);
    return rows.isEmpty ? null : jsonDecode(rows.first['data']!.asString) as Map<String, Object?>;
  }

  Map<String, Object?> _encode(T data, [Map<String, Object?>? existing]) {
    try {
      final fields = _resolveFieldValues(data.toJson(), existing);
      return jsonDecode(jsonEncode(fields, toEncodable: _toEncodable)) as Map<String, Object?>;
    } catch (error) {
      throw ArgumentError('${data.runtimeType}.toJson() holds a value that cannot be stored: $error');
    }
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;

  Future<void> _create(_Executor executor, String tenant, T data) {
    final now = _now;
    return executor
        .execute('INSERT INTO "${parent.name}" (tenant, id, data, created_at, updated_at) VALUES (?, ?, ?, ?, ?)', [
          DatabaseType.varchar(tenant),
          DatabaseType.varchar(id),
          DatabaseType.varchar(jsonEncode(_encode(data))),
          DatabaseType.integer(now),
          DatabaseType.integer(now),
        ]);
  }

  Future<void> _set(_Executor executor, String tenant, T data, bool merge) async {
    final existing = merge ? await _load(executor, tenant) : null;
    var fields = _encode(data, existing);
    if (existing != null) fields = _deepMerge(existing, fields);
    final now = _now;
    await executor.execute(
      'INSERT OR IGNORE INTO "${parent.name}" (tenant, id, data, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
      [
        DatabaseType.varchar(tenant),
        DatabaseType.varchar(id),
        DatabaseType.varchar(jsonEncode(fields)),
        DatabaseType.integer(now),
        DatabaseType.integer(now),
      ],
    );
    await _replace(executor, tenant, fields, now);
  }

  Future<void> _update(_Executor executor, String tenant, List<FieldChange> changes) async {
    final existing = await _load(executor, tenant) ?? (throw DocumentNotFoundError(parent.name, id));
    _applyUpdates(existing, changes);
    await _replace(executor, tenant, existing, _now);
  }

  Future<void> _replace(_Executor executor, String tenant, Map<String, Object?> fields, int now) =>
      executor.execute('UPDATE "${parent.name}" SET data = ?, updated_at = ? WHERE tenant = ? AND id = ?', [
        DatabaseType.varchar(jsonEncode(fields)),
        DatabaseType.integer(now),
        DatabaseType.varchar(tenant),
        DatabaseType.varchar(id),
      ]);

  Future<void> _delete(_Executor executor, String tenant) => executor.execute(
    'DELETE FROM "${parent.name}" WHERE tenant = ? AND id = ?',
    [DatabaseType.varchar(tenant), DatabaseType.varchar(id)],
  );
}

/// The changes [build] composes, which must not be none at all.
List<FieldChange> _changesOf(List<FieldChange> Function(UpdateBuilder u) build) {
  final changes = build(const UpdateBuilder._());
  if (changes.isEmpty) throw ArgumentError.value(changes, 'changes', 'cannot be empty');
  return changes;
}
