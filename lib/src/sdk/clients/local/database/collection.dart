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

/// The table [Collection]s record themselves in, so [Tenant] can find the
/// isolated ones without a project listing them.
const _registryTable = 'pylon_collections';

/// Every document of one kind, stored in one SQLite table named [name].
///
/// Declared once, as a field of a project's own [Database]:
///
/// ```dart
/// final users = Collection<User>('users', User.fromJson);
/// final catalogue = Collection<Product>('catalogue', Product.fromJson, tunnel: Tunnel.shared);
/// ```
///
/// [fromJson] rebuilds a [T] from a document's id and stored fields; [T]'s own
/// [Model.toJson] writes it back. The table is created the first time the
/// collection is used, with `CREATE TABLE IF NOT EXISTS` — a table of that
/// name that already exists but was not made by a [Collection] fails with a
/// [StateError] rather than being written over.
///
/// Whose documents it holds is its [tunnel]'s call: by default those of the
/// current [Tenant] only, so two accounts on one device never see each
/// other's data.
///
/// A [Collection] is also the [Query] that matches all of its documents, so
/// everything a [Query] offers is available on it directly.
final class Collection<T extends Model> extends Query<T> {
  /// The collection called [name], whose documents [fromJson] rebuilds.
  ///
  /// [name] is the table's own name: letters, digits and `_`, not starting
  /// with a digit, `sqlite_` or `pylon_`. Each of [indexes] is a [Field] or
  /// [ListField] to keep an index on,
  /// which is what makes filtering or ordering on it fast in a large
  /// collection. [tunnel] says whose documents it holds.
  Collection(
    this.name,
    T Function(String id, Map<String, Object?> json) fromJson, {
    this.indexes = const [],
    this.tunnel = Tunnel.isolated,
  }) : _fromJson = fromJson,
       super._(null, const _QuerySpec(), const _CurrentScope()) {
    final lower = name.toLowerCase();
    if (!_collectionName.hasMatch(name) || lower.startsWith('sqlite_') || lower.startsWith('pylon_')) {
      throw ArgumentError.value(
        name,
        'name',
        'must be letters, digits and "_", not starting with a digit, "sqlite_" or "pylon_"',
      );
    }
    for (final index in indexes) {
      _segmentsOf(index);
    }
  }

  Collection._view(Collection<T> base, _Scope scope)
    : name = base.name,
      indexes = base.indexes,
      tunnel = base.tunnel,
      _fromJson = base._fromJson,
      super._(null, const _QuerySpec(), scope);

  /// The collection's name, and the name of the table behind it.
  final String name;

  /// The fields this collection keeps an index on, as given.
  final List<FieldReference> indexes;

  /// Whose documents this collection holds.
  final Tunnel tunnel;

  final T Function(String id, Map<String, Object?> json) _fromJson;

  static final _random = Random.secure();
  static const _idAlphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  Object? _preparedFor;
  Future<void>? _prepared;

  /// This collection as [tenant] sees it, whichever tenant is current: the
  /// same documents a [Tenant.use] of [tenant] would show, read and written
  /// directly.
  ///
  /// The way to reach one account's documents on purpose — a background sync
  /// of an account that is not the one on screen, say. Throws a [StateError]
  /// on a [Tunnel.shared] collection, which has no tenants.
  @override
  Collection<T> inTenant(String tenant) {
    _checkTenantId(tenant);
    _requireIsolated(this, 'inTenant');
    return Collection._view(this, _PinnedScope(tenant));
  }

  /// The document [id] of this collection.
  ///
  /// Reads and writes nothing until asked to: the document need not exist.
  /// Which tenant's it is is decided by each operation, when it starts.
  DocumentReference<T> doc(String id) {
    if (id.isEmpty || id == '.' || id == '..' || id.contains('/')) {
      throw ArgumentError.value(id, 'id', 'must be non-empty, not "." or "..", and without "/"');
    }
    return DocumentReference._(this, id);
  }

  /// A fresh, random, 20-character id, the way Firestore makes one.
  String newId() =>
      String.fromCharCodes(Iterable.generate(20, (_) => _idAlphabet.codeUnitAt(_random.nextInt(_idAlphabet.length))));

  /// Stores [data] as a new document, under [Model.id] — or under a fresh
  /// [newId] when that is empty — and answers its reference.
  ///
  /// Throws a `DatabaseUniqueConstraintError` when a document already has
  /// that id: use [DocumentReference.set] to overwrite one.
  Future<DocumentReference<T>> add(T data) async {
    final reference = doc(data.id.isEmpty ? newId() : data.id);
    final tenant = reference._tenant;
    await reference._run((executor) => reference._create(executor, tenant, data));
    return reference;
  }

  /// Removes every document of the tenant this collection reaches, keeping
  /// the table, its indexes, and every other tenant's documents.
  Future<void> clear() async {
    final tenant = _scope.reach(this).tenant!;
    await _ensure();
    await AppStorage.execute('DELETE FROM "$name" WHERE tenant = ?', [DatabaseType.varchar(tenant)]);
    _ChangeBus.notify(name);
  }

  /// Removes the table and everything in it, indexes included — **for every
  /// tenant**, not only the current one.
  ///
  /// The collection stays usable: the next read or write creates the table
  /// again, empty, and a [Query.snapshots] listener hears the collection
  /// empty out.
  Future<void> drop() async {
    await _ensure();
    await AppStorage.execute('DROP TABLE IF EXISTS "$name"');
    await AppStorage.execute('DELETE FROM "$_registryTable" WHERE name = ?', [DatabaseType.varchar(name)]);
    _prepared = null;
    _preparedFor = null;
    _ChangeBus.notify(name);
  }

  /// Creates the table and its indexes once per [AppStorage], checking first
  /// that a table already there is one of ours.
  Future<void> _ensure() {
    final generation = AppStorage.generation;
    final held = _prepared;
    if (held != null && identical(_preparedFor, generation)) return held;

    _preparedFor = generation;
    final prepared = _prepare();
    _prepared = prepared;
    unawaited(
      prepared.catchError((Object _) {
        if (identical(_prepared, prepared)) _prepared = null;
      }),
    );
    return prepared;
  }

  static const _columns = {'tenant', 'id', 'data', 'created_at', 'updated_at'};
  static const _legacyColumns = {'id', 'data', 'created_at', 'updated_at'};

  Future<void> _prepare() async {
    final columns = {for (final column in await AppStorage.columns(name)) column.name};
    if (columns.length == _legacyColumns.length && columns.containsAll(_legacyColumns)) {
      await _migrateLegacyTable();
    } else if (columns.isNotEmpty && !(columns.length == _columns.length && columns.containsAll(_columns))) {
      throw StateError(
        'A table named "$name" already exists and is not a Collection\'s: it has the columns '
        '${columns.join(', ')}, where a Collection needs ${_columns.join(', ')}.',
      );
    }
    await _createTable(const _StorageExecutor());
  }

  /// Rebuilds a table made before tenants existed — no `tenant` column — with
  /// every document in the anonymous partition, which is what they were.
  Future<void> _migrateLegacyTable() => _atomically((executor) async {
    await executor.execute(_tableSql('${name}__new'));
    await executor.execute(
      'INSERT INTO "${name}__new" (tenant, id, data, created_at, updated_at) '
      "SELECT '', id, data, created_at, updated_at FROM \"$name\"",
    );
    await executor.execute('DROP TABLE "$name"');
    await executor.execute('ALTER TABLE "${name}__new" RENAME TO "$name"');
  });

  String _tableSql(String table) =>
      'CREATE TABLE IF NOT EXISTS "$table" ('
      "tenant TEXT NOT NULL DEFAULT '', "
      'id TEXT NOT NULL, '
      'data TEXT NOT NULL, '
      'created_at INTEGER NOT NULL, '
      'updated_at INTEGER NOT NULL, '
      'PRIMARY KEY (tenant, id))';

  /// Creates the table, its indexes and its registry entry when missing, on
  /// [executor].
  Future<void> _createTable(_Executor executor) async {
    await executor.execute(_tableSql(name));
    for (final index in indexes) {
      await executor.execute(
        'CREATE INDEX IF NOT EXISTS "${name}_${_segmentsOf(index).join('_')}_idx" '
        'ON "$name" (tenant, ${_fieldExpression(index)})',
      );
    }
    await executor.execute(
      'CREATE TABLE IF NOT EXISTS "$_registryTable" (name TEXT PRIMARY KEY NOT NULL, tunnel TEXT NOT NULL)',
    );
    await executor.execute('INSERT OR REPLACE INTO "$_registryTable" (name, tunnel) VALUES (?, ?)', [
      DatabaseType.varchar(name),
      DatabaseType.varchar(tunnel.name),
    ]);
  }

  /// Decodes [row]. With [pinRows], the reference of the snapshot is pinned
  /// to the tenant the row belongs to, so writing through it lands on that
  /// tenant whatever is current.
  QueryDocumentSnapshot<T> _documentOf(DatabaseRow row, {bool pinRows = false}) {
    final id = row['id']!.asString;
    final raw = row['data']!.asString;
    final tenant = row['tenant']!.asString;
    final json = jsonDecode(raw) as Map<String, Object?>;
    return QueryDocumentSnapshot._(
      (pinRows ? Collection._view(this, _PinnedScope(tenant)) : this).doc(id),
      raw: raw,
      json: json,
      data: _fromJson(id, json),
      tenant: tenant.isEmpty ? null : tenant,
      createTime: DateTime.fromMillisecondsSinceEpoch(row['created_at']!.asInt, isUtc: true),
      updateTime: DateTime.fromMillisecondsSinceEpoch(row['updated_at']!.asInt, isUtc: true),
    );
  }
}
