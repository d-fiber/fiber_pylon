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

/// How a [Collection] keeps its documents apart between accounts.
enum Tunnel {
  /// Every tenant has documents of its own. What one tenant writes is
  /// invisible to every other — under the same id, with the same content, or
  /// not — and switching [Tenant] switches what the collection holds.
  ///
  /// The default: mixing accounts has to be asked for, never fall out of
  /// forgetting to say otherwise. Without a current [Tenant] it holds the
  /// device's anonymous, signed-out documents.
  isolated,

  /// One copy for everyone, whichever [Tenant] is current: a catalogue, a
  /// setting of the device rather than of an account.
  shared,
}

/// What [Tenant.transfer] does when a document of [Tenant.transfer]'s `from`
/// has the same id as one already held by its `to`.
enum TransferConflict {
  /// The document already at the target stays; the source one is dropped.
  keepTarget,

  /// The source document replaces the one at the target.
  keepSource,
}

/// Whose documents the [Collection]s of a [Tunnel.isolated] tunnel hold right
/// now — the signed-in account, in an app that has one.
///
/// ```dart
/// Tenant.use(account.id);  // on sign-in: every isolated collection now holds this account's documents
/// Tenant.leave();          // on sign-out: back to the anonymous ones, never the previous account's
/// ```
///
/// Pylon holds no opinion about what a tenant id is: an account id, a
/// profile name, a workspace. The current tenant is not remembered across
/// launches; the project that knows who is signed in calls [use] at startup.
///
/// An operation started while one tenant is current finishes on that tenant,
/// even if [use] is called before it does, and a `snapshots()` listener on an
/// isolated collection is handed the new tenant's documents from scratch — the
/// previous tenant's are never carried over into it.
abstract final class Tenant {
  static String? _current;
  static final StreamController<String?> _changes = StreamController<String?>.broadcast();

  /// The current tenant, or `null` when there is none.
  static String? get current => _current;

  /// Every change of [current], in order.
  static Stream<String?> get changes => _changes.stream;

  /// Makes [id] the current tenant.
  ///
  /// Throws an [ArgumentError] when [id] is empty. Does nothing when [id] is
  /// already current.
  static void use(String id) {
    _checkTenantId(id);
    if (_current == id) return;
    _current = id;
    _changes.add(id);
  }

  /// Leaves the current tenant: isolated collections hold the anonymous
  /// documents again.
  static void leave() {
    if (_current == null) return;
    _current = null;
    _changes.add(null);
  }

  /// Every tenant that holds at least one document in an isolated collection,
  /// sorted. The anonymous documents belong to no tenant and are not listed.
  static Future<List<String>> list() async {
    final tenants = <String>{};
    for (final table in await _isolatedTables(const _StorageExecutor())) {
      final rows = await AppStorage.rawQuery("SELECT DISTINCT tenant FROM \"$table\" WHERE tenant != ''");
      tenants.addAll(rows.map((row) => row['tenant']!.asString));
    }
    return tenants.toList()..sort();
  }

  /// Removes every document [id] holds, in every isolated collection, at
  /// once: the account is deleted, or signed out for good.
  ///
  /// Shared collections are not touched. Removing the current tenant's
  /// documents is allowed, and its listeners hear the collections empty out.
  static Future<void> purge(String id) async {
    _checkTenantId(id);
    final tables = await _atomically((executor) async {
      final tables = await _isolatedTables(executor);
      for (final table in tables) {
        await executor.execute('DELETE FROM "$table" WHERE tenant = ?', [DatabaseType.varchar(id)]);
      }
      return tables;
    });
    tables.forEach(_ChangeBus.notify);
  }

  /// Moves every document [from] holds, in every isolated collection, to [to],
  /// answering how many documents moved. Nothing is left under [from].
  ///
  /// A `null` [from] or [to] is the anonymous documents: the usual case is
  /// carrying what was saved before signing in over to the account that just
  /// did — `Tenant.transfer(to: account.id)` — and the reverse mixes two
  /// accounts' data on purpose, which is why it is spelled out. Shared
  /// collections are not touched. [onConflict] decides what happens to a
  /// document [to] already holds under the same id.
  static Future<int> transfer({
    String? from,
    String? to,
    TransferConflict onConflict = TransferConflict.keepTarget,
  }) async {
    if (from != null) _checkTenantId(from);
    if (to != null) _checkTenantId(to);
    if (from == to) throw ArgumentError('from and to are the same tenant: $from');

    final source = DatabaseType.varchar(from ?? '');
    final target = DatabaseType.varchar(to ?? '');
    final result = await _atomically((executor) async {
      var moved = 0;
      final tables = await _isolatedTables(executor);
      for (final table in tables) {
        if (onConflict == TransferConflict.keepSource) {
          await executor.execute(
            'DELETE FROM "$table" WHERE tenant = ? AND id IN (SELECT id FROM "$table" WHERE tenant = ?)',
            [target, source],
          );
        }
        await executor.execute('UPDATE OR IGNORE "$table" SET tenant = ? WHERE tenant = ?', [target, source]);
        moved += (await executor.rawQuery('SELECT changes() AS moved')).single['moved']!.asInt;
        await executor.execute('DELETE FROM "$table" WHERE tenant = ?', [source]);
      }
      return (tables: tables, moved: moved);
    });
    result.tables.forEach(_ChangeBus.notify);
    return result.moved;
  }
}

void _checkTenantId(String id) {
  if (id.isEmpty) throw ArgumentError.value(id, 'id', 'cannot be empty');
}

/// The tables of every isolated [Collection] this database file has ever
/// prepared and still holds.
Future<List<String>> _isolatedTables(_Executor executor) async {
  final registry = await executor.rawQuery("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", [
    const DatabaseType.varchar(_registryTable),
  ]);
  if (registry.isEmpty) return const [];
  final rows = await executor.rawQuery(
    'SELECT c.name AS name FROM "$_registryTable" c '
    "JOIN sqlite_master m ON m.type = 'table' AND m.name = c.name WHERE c.tunnel = ?",
    [DatabaseType.varchar(Tunnel.isolated.name)],
  );
  return [for (final row in rows) row['name']!.asString];
}

/// Whose documents a [Query] or [DocumentReference] reaches.
sealed class _Scope {
  const _Scope();

  /// The partitions this scope reaches right now on [collection], resolved
  /// at the moment an operation starts and held for its whole length.
  _Reach reach(Collection<Model> collection);
}

/// Whoever [Tenant.current] is, whenever the operation runs.
final class _CurrentScope extends _Scope {
  const _CurrentScope();

  @override
  _Reach reach(Collection<Model> collection) =>
      _Reach.one(collection.tunnel == Tunnel.shared ? '' : Tenant.current ?? '');
}

/// One tenant, whichever is current.
final class _PinnedScope extends _Scope {
  const _PinnedScope(this.tenant);

  final String tenant;

  @override
  _Reach reach(Collection<Model> collection) {
    _requireIsolated(collection, 'inTenant');
    return _Reach.one(tenant);
  }

  @override
  bool operator ==(Object other) => other is _PinnedScope && other.tenant == tenant;

  @override
  int get hashCode => tenant.hashCode;
}

/// Every tenant, or just [only].
final class _AllScope extends _Scope {
  const _AllScope(this.only);

  final Set<String>? only;

  @override
  _Reach reach(Collection<Model> collection) {
    _requireIsolated(collection, 'acrossTenants');
    return _Reach.many(only);
  }
}

void _requireIsolated(Collection<Model> collection, String method) {
  if (collection.tunnel == Tunnel.shared) {
    throw StateError('"${collection.name}" is a shared collection: it has no tenants, so $method does not apply.');
  }
}

/// The partitions of a collection one operation reads or writes.
final class _Reach {
  const _Reach.one(String this.tenant) : only = null, isMany = false;

  const _Reach.many(this.only) : tenant = null, isMany = true;

  /// The single partition, when [isMany] is `false`.
  final String? tenant;

  /// The partitions reached when [isMany]: `null` is all of them.
  final Set<String>? only;

  final bool isMany;

  @override
  bool operator ==(Object other) =>
      other is _Reach &&
      other.isMany == isMany &&
      other.tenant == tenant &&
      ((other.only == null && only == null) ||
          (other.only != null && only != null && other.only!.length == only!.length && other.only!.containsAll(only!)));

  @override
  int get hashCode => Object.hash(isMany, tenant, only?.length);
}
