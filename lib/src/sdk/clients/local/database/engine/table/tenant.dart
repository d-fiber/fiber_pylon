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

part of '../database.dart';

/// How a [TypedTable] keeps its rows apart between accounts.
enum Tunnel {
  /// Every tenant has rows of its own.
  ///
  /// What one tenant writes is invisible to every other, whether it uses the
  /// same key and the same content or not, and switching [Tenant] switches what
  /// the table holds.
  ///
  /// Without a current [Tenant] such a table holds the anonymous, signed-out
  /// rows.
  isolated,

  /// One copy for everyone, whichever [Tenant] is current. The default of a
  /// [TypedTable], which adds nothing to the table's schema.
  shared,
}

/// What [WholeAccess.transfer] and [LocalDatabaseTenants.adoptAnonymousRows]
/// do when a row being moved collides with one already at the target, on the
/// key or on a unique constraint.
enum TransferConflict {
  /// The row already at the target stays and the source one is dropped.
  keepTarget,

  /// The source row replaces the one at the target.
  keepSource,
}

/// Whose rows the [Tunnel.isolated] tables of a [LocalDatabase] hold right now:
/// the signed-in account, in an app that has one.
///
/// There are two mechanisms, and they do not mix. Reading through [TypedTable.on]
/// is the tenant mechanism: it reaches the current tenant's rows and nothing
/// else, and no call on what it returns can reach another tenant's, not a row,
/// not a count, not the name of a tenant. Reading the whole database is another
/// mechanism, [TypedTable.onWholeDatabase] and
/// [LocalDatabaseTenants.wholeDatabase], which you pick on purpose and which
/// reaches every tenant.
///
/// ```dart
/// Tenant.use(account.id);
/// Tenant.leave();
/// ```
///
/// After [use], on sign-in, every isolated table holds that account's rows.
/// After [leave], on sign-out, they hold the anonymous rows again and never the
/// previous account's.
///
/// A tenant id is any non-empty string: an account id, a profile name, a
/// workspace. The current tenant is not remembered across launches, so the
/// project that knows who is signed in calls [use] at startup, or hands that to
/// the credential it already keeps with [follow].
///
/// An operation started while one tenant is current finishes on that tenant,
/// even if [use] is called before it does. A `watch()` on an isolated table is
/// handed the new tenant's rows from scratch, and the previous tenant's are
/// never carried over into it.
abstract final class Tenant {
  /// Backs [current].
  static String? _current;

  /// Backs [changes].
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

  /// Leaves the current tenant: isolated tables hold the anonymous rows again.
  static void leave() {
    if (_current == null) return;
    _current = null;
    _changes.add(null);
  }

  /// Makes the current tenant the holder of the app's `Credentials`, for as long
  /// as the returned subscription is not cancelled.
  ///
  /// The tenant is [use]d for each credential that names a `holder`, and left
  /// when the credential is cleared or names nobody, which is what a sign-in and
  /// a sign-out come down to. A renewal that keeps the same holder changes
  /// nothing. The credential in force is taken at once, so a credential restored
  /// from the vault before `configureSdk` returned already sets the tenant.
  ///
  /// ```dart
  /// await configureSdk();
  /// Tenant.follow();
  /// ```
  ///
  /// Needs `configureSdk` to have run, since that is what makes `Credentials`
  /// available.
  static StreamSubscription<void> follow() {
    void apply(Credential? credential) {
      final holder = credential?.holder;
      holder == null ? leave() : use(holder);
    }

    // Applied now rather than through the subscription, whose first value, the
    // credential in force, only arrives a moment after it starts.
    apply(Credentials.value);
    return Credentials.stream.skip(1).listen(apply);
  }
}

void _checkTenantId(String id) {
  if (id.isEmpty) throw ArgumentError.value(id, 'id', 'cannot be empty');
}

/// The hidden column an isolated table gains to hold the tenant of each row.
///
/// Reserved: a table cannot declare a column of this name.
const String _tenantColumn = '__tenant';

/// Whose rows a read or write of a table reaches.
sealed class _Scope {
  const _Scope();

  /// The partitions this scope reaches right now on [table], resolved at the
  /// moment an operation starts and held for its whole length.
  _Reach reach(TypedTable<Object> table);
}

/// Whoever [Tenant.current] is, whenever the operation runs.
final class _CurrentScope extends _Scope {
  const _CurrentScope();

  @override
  _Reach reach(TypedTable<Object> table) => _Reach.one(table.tunnel == Tunnel.shared ? '' : Tenant.current ?? '');
}

/// One tenant, whichever is current: how the whole-database mechanism narrows
/// itself to a tenant, and how an operation holds on to the one it started on.
final class _PinnedScope extends _Scope {
  const _PinnedScope(this.tenant);

  final String tenant;

  @override
  _Reach reach(TypedTable<Object> table) => _Reach.one(table.tunnel == Tunnel.shared ? '' : tenant);

  @override
  bool operator ==(Object other) => other is _PinnedScope && other.tenant == tenant;

  @override
  int get hashCode => tenant.hashCode;
}

/// Every tenant, or just [only]: the whole-database mechanism.
final class _AllScope extends _Scope {
  const _AllScope(this.only);

  final Set<String>? only;

  @override
  _Reach reach(TypedTable<Object> table) => _Reach.many(only);
}

/// The partitions of a table one operation reads or writes.
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

/// What only the tenant mechanism offers on a [LocalDatabase]: operations on
/// the rows of the current tenant and of the anonymous session, which never
/// read or touch another tenant's.
extension LocalDatabaseTenants on LocalDatabase {
  /// Moves every anonymous row to the current tenant, in every isolated table,
  /// and answers how many moved.
  ///
  /// The anonymous rows are what was saved before anyone signed in, so this is
  /// the usual step of a first sign-in. Nothing is left anonymous afterwards.
  /// [onConflict] decides what happens to a row the tenant already holds under
  /// the same key or the same unique value, and a row dropped that way is not
  /// counted.
  ///
  /// Throws a [StateError] when there is no current [Tenant].
  Future<int> adoptAnonymousRows({TransferConflict onConflict = TransferConflict.keepTarget}) {
    final tenant = Tenant.current;
    if (tenant == null) throw StateError('adoptAnonymousRows needs a current tenant: call Tenant.use first.');
    return _moveRows(null, tenant, onConflict);
  }

  /// Deletes every row of the current tenant from every isolated table, for when
  /// the account is deleted.
  ///
  /// The anonymous rows and the shared tables are not touched. Throws a
  /// [StateError] when there is no current [Tenant].
  Future<void> purgeCurrentTenant() {
    final tenant = Tenant.current;
    if (tenant == null) throw StateError('purgeCurrentTenant needs a current tenant: call Tenant.use first.');
    return _purgeRows(tenant);
  }

  /// The whole-database mechanism, for what is not one tenant's business:
  /// listing the tenants, removing one's rows, moving rows from one tenant to
  /// another.
  ///
  /// It is a separate entry point on purpose, and nothing reachable through
  /// [TypedTable.on] leads here. It takes the app's [Fingerprint], which must be
  /// the one this database was opened with. Throws a [StateError] when it was
  /// opened with none, or with another.
  WholeAccess wholeDatabase(Fingerprint fingerprint) {
    _requireFingerprint(fingerprint);
    return WholeAccess._(this);
  }

  Iterable<String> get _isolatedTableNames => [
    for (final table in _tables ?? const <TypedTable<Object>>[])
      if (table.tunnel == Tunnel.isolated) table.tableName,
  ];

  /// Moves every row [from] holds to [to] in every isolated table, `null` being
  /// the anonymous rows.
  ///
  /// The foreign keys are checked when the transaction commits, since a row and
  /// the rows that point at it change tenant one statement apart.
  Future<int> _moveRows(String? from, String? to, TransferConflict onConflict) {
    final source = Value.varchar(from ?? '');
    final target = Value.varchar(to ?? '');
    final tables = _isolatedTableNames.toList();
    return runTransaction((txn) async {
      await txn._txn.execute('PRAGMA defer_foreign_keys = ON');
      var moved = 0;
      for (final table in tables) {
        final quoted = _quotedIdentifier(table);
        final tenant = _quotedIdentifier(_tenantColumn);
        final conflict = onConflict == TransferConflict.keepSource ? 'REPLACE' : 'IGNORE';
        moved += await txn._txn.rawUpdate('UPDATE OR $conflict $quoted SET $tenant = ? WHERE $tenant = ?', [
          target._toNative(),
          source._toNative(),
        ]);
        await txn._txn.rawDelete('DELETE FROM $quoted WHERE $tenant = ?', [source._toNative()]);
      }
      _notifyWrite(tables.toSet());
      return moved;
    });
  }

  /// Deletes every row [tenantId] holds from every isolated table.
  ///
  /// The foreign keys are checked when the transaction commits, since the tables
  /// are emptied one after the other.
  Future<void> _purgeRows(String tenantId) {
    final tables = _isolatedTableNames.toList();
    return runTransaction((txn) async {
      await txn._txn.execute('PRAGMA defer_foreign_keys = ON');
      for (final table in tables) {
        await txn._txn.rawDelete(
          'DELETE FROM ${_quotedIdentifier(table)} WHERE ${_quotedIdentifier(_tenantColumn)} = ?',
          [tenantId],
        );
      }
      _notifyWrite(tables.toSet());
    });
  }
}

/// The operations that concern every tenant of a [LocalDatabase] at once,
/// opened by [LocalDatabaseTenants.wholeDatabase].
final class WholeAccess {
  const WholeAccess._(this._database);

  /// The database these operations run on.
  final LocalDatabase _database;

  /// Every tenant that holds at least one row in an isolated table, sorted.
  /// The anonymous rows belong to no tenant and are not listed.
  Future<List<String>> tenants() async {
    final tenants = <String>{};
    for (final table in _database._isolatedTableNames) {
      final rows = await _database.runRawQuery(
        'SELECT DISTINCT ${_quotedIdentifier(_tenantColumn)} AS tenant FROM ${_quotedIdentifier(table)} '
        "WHERE ${_quotedIdentifier(_tenantColumn)} != ''",
      );
      tenants.addAll(rows.map((row) => row['tenant']!.asString));
    }
    return tenants.toList()..sort();
  }

  /// Deletes every row [tenant] holds from every isolated table, and nothing
  /// else.
  ///
  /// The shared tables and the anonymous rows are not touched. Throws an
  /// [ArgumentError] when [tenant] is empty.
  Future<void> purge(String tenant) {
    _checkTenantId(tenant);
    return _database._purgeRows(tenant);
  }

  /// Moves every row [from] holds to [to], in every isolated table, and answers
  /// how many moved.
  ///
  /// A `null` [from] or [to] is the anonymous rows. Nothing is left under
  /// [from], and the shared tables are not touched. [onConflict] decides what
  /// happens to a row [to] already holds under the same key or the same unique
  /// value, and a row dropped that way is not counted.
  ///
  /// This is the one call that mixes two tenants' data, which is why it lives
  /// here and not on the tenant mechanism. Throws an [ArgumentError] when [from]
  /// or [to] is empty, or when they are the same.
  Future<int> transfer({String? from, String? to, TransferConflict onConflict = TransferConflict.keepTarget}) {
    if (from != null) _checkTenantId(from);
    if (to != null) _checkTenantId(to);
    if (from == to) throw ArgumentError('from and to are the same tenant: $from');
    return _database._moveRows(from, to, onConflict);
  }
}
