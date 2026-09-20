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

// What a project sees of pylon is the barrel, and only the barrel. This checks
// that with the analyzer itself, on programs that import nothing else: the
// engine is the package's own plumbing, so a project neither opens a database
// by hand nor builds a schema with the DSL, and it can do everything it is
// meant to — declare a table, read it with from, switch tenant, reach the app
// database with the app's fingerprint.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _refusedWarnings = {
  'INVALID_USE_OF_VISIBLE_FOR_TESTING_MEMBER',
  'INVALID_OVERRIDE_OF_NON_VIRTUAL_MEMBER',
  'INVALID_USE_OF_PROTECTED_MEMBER',
};

const _prelude = '''
import 'package:fiber_pylon/fiber_pylon.dart';

final class Note {
  const Note({required this.id, required this.title});

  final String id;
  final String title;
}

final class Notes extends KeyedTable<Note, String> {
  Notes() : super('notes');

  late final id = column.text('id').primaryKey();
  late final title = column.text('title');

  @override
  Tunnel get tunnel => Tunnel.isolated;

  @override
  List<Field<Object?>> get columns => [id, title];

  @override
  Note read(Reader row) => Note(id: row(id), title: row(title));

  @override
  List<Assignment> write(Note note) => [id.to(note.id), title.to(note.title)];
}

final class Own extends Database {
  final notes = Notes();

  @override
  List<KeyedTable<Object, Object>> get tables => [notes];
}

Future<void> program(Own db) async {
''';

final class _Program {
  const _Program(this.name, this.body, {required this.compiles});

  final String name;
  final String body;
  final bool compiles;

  String get source => '$_prelude$body\n}\n';
}

const _programs = [
  _Program('a table and a typed query', '''
await db.from(db.notes).where(db.notes.title.isEqualTo('a')).orderBy((o) => o.asc(db.notes.title)).select();
''', compiles: true),
  _Program('a write, an update and a delete', '''
await db.from(db.notes).upsert(const Note(id: 'a', title: 't'));
await db.from(db.notes).where(db.notes.id.isEqualTo('a')).update([db.notes.title.to('u')]);
await db.from(db.notes).remove('a');
''', compiles: true),
  _Program('a watched query', '''
db.from(db.notes).where(db.notes.title.isEqualTo('a')).stream().listen((notes) => notes.length);
''', compiles: true),
  _Program('switching tenant', '''
Tenant.use('account');
Tenant.leave();
''', compiles: true),
  _Program('a batch and a transaction', '''
await (db.batch()
      ..insert(db.notes, const Note(id: 'a', title: 't'))
      ..update(db.notes, 'a', [db.notes.title.to('u')])
      ..remove(db.notes, 'a'))
    .commit();
await db.runTransaction((tx) => tx.from(db.notes).get('a'));
''', compiles: true),
  _Program('a table across every tenant', '''
await db.fromWholeDatabase(db.notes, SecureStorage.fingerprint).select();
''', compiles: true),
  _Program('reaching the whole database with the app fingerprint', '''
await db.wholeDatabase(SecureStorage.fingerprint).tenants();
await LocalDatabase.tableNames();
''', compiles: true),
  _Program('reading the encryption of the app database', '''
LocalDatabase.encryption = EncryptionPolicy.required;
print(LocalDatabase.isEncrypted);
''', compiles: true),
  _Program('a secret entry through the static factories', '''
final token = SecureStorage.string_('token', '');
await token.set('abc');
print(token());
print(SecureStorage.fingerprint.derive('purpose'));
''', compiles: true),
  _Program('a call that reads the cache and refreshes it', '''
Repository<int, int, String, int>? call;
call?.status.stream.listen((status) => switch (status) {
  StatusIdle() => 0,
  StatusRunning() => 1,
  StatusSucceeded() => 2,
  StatusOffline() => 3,
  StatusUnauthenticated() => 4,
  StatusFailed(:final error) => error,
});
call?.data.stream.listen((value) => (value ?? 0) + 1);
await call?.refresh();
''', compiles: true),
  _Program('the connection through the singleton', '''
print(Network.isReachable.value);
Network.isReachable.stream.listen((reachable) => print(reachable));
''', compiles: true),
  _Program('building the connection state by hand', 'Network.forTesting(reachable: true);', compiles: false),
  _Program('reading a connectivity report by hand', 'Network.reads(const []);', compiles: false),
  _Program('overriding the data a repository hands out', '''
}

abstract base class Overriding extends Repository<int, int, String, int> {
  @override
  Observable<int?> get data => throw UnimplementedError();
''', compiles: false),
  _Program('overriding the status a repository hands out', '''
}

abstract base class Overriding extends Repository<int, int, String, int> {
  @override
  Observable<Status<String>> get status => throw UnimplementedError();
''', compiles: false),
  _Program('a repository that overrides only what it is meant to', '''
}

abstract base class Reading extends Repository<int, int, String, int> {
  @override
  bool get requiresConnection => false;

  @override
  Stream<int?> stream() => const Stream<int?>.empty();
''', compiles: true),
  _Program('reaching the client of a REST sdk from outside it', '''
}

final class Api extends RestSdk<int> {
  Api(super.client);
}

void reaching(Api api) {
  print(api.client);
''', compiles: false),
  _Program('a REST sdk that builds its nodes from its own client', '''
}

final class Api extends RestSdk<int> {
  Api(super.client);

  late final RestNode<int> users = RestNode<int>(client);
''', compiles: true),
  _Program('overriding the client of a REST sdk', '''
}

final class Api extends RestSdk<int> {
  Api(super.client);

  @override
  RestClient<int> get client => throw UnimplementedError();
''', compiles: false),
  _Program('the app credential through the singleton', '''
await Credentials.set(const Credential(token: 'abc', refreshToken: 'again'));
print(Credentials.isHeld);
print(Credentials.value?.token);
Credentials.held.stream.listen((held) => print(held));
Credentials.stream.listen((credential) => print(credential));
Credentials.renewWith(refresh: (current) async => current, fatalSignals: {Object()});
Tenant.follow();
await Credentials.clear();
''', compiles: true),
  _Program(
    'the machinery behind the credential singleton',
    'CredentialManager<Credential, Object>? manager;',
    compiles: false,
  ),
  _Program('a credential store', 'MemoryCredentialStore<Credential>? store;', compiles: false),
  _Program('a stored credential', 'StoredCredential<Credential>? store;', compiles: false),
  _Program('a credential refresher', 'CredentialRefresher<Credential>? refresher;', compiles: false),
  _Program('an ordering written as a list of sorts', '''
await db.from(db.notes).orderBy([db.notes.title.asc()]).select();
''', compiles: false),
  _Program('an ordering with several terms in cascade', '''
await db.from(db.notes).orderBy((o) => o.asc(db.notes.title).desc(db.notes.id)).select();
''', compiles: true),
  _Program('a table read as a stream', '''
db.from(db.notes).orderBy((o) => o.asc(db.notes.title)).stream().listen((notes) => notes.length);
db.from(db.notes).streamFirst();
db.from(db.notes).streamCount();
db.from(db.notes).streamOne('a');
''', compiles: true),
  _Program('building a secret entry by hand', "Secure.string_(SecureStorage.fingerprint, 'k', '');", compiles: false),
  _Program('a vault of one\'s own', 'const SecretStore? vault = null;', compiles: false),
  _Program('the fingerprint as bytes', 'SecureStorage.fingerprint.deriveHex(\'x\');', compiles: false),
  _Program('the fingerprint error type', 'const FingerprintError? error = null;', compiles: false),
  _Program('opening a database by hand', "LocalDatabase.forTesting(name: 'x.db');", compiles: false),
  _Program(
    'declaring tables on a database by hand',
    "LocalDatabase.declaredForTesting(name: 'x.db', tables: []);",
    compiles: false,
  ),
  _Program('building a schema with the DSL', "TableBuilder('t');", compiles: false),
  _Program('a schema migration', 'const Migration? migration = null;', compiles: false),
  _Program('a drift report', 'const DifferenceKind? kind = null;', compiles: false),
];

Future<Map<String, List<String>>> _analyzeEachProgram(Directory directory) async {
  for (var index = 0; index < _programs.length; index++) {
    await File('${directory.path}/program_$index.dart').writeAsString(_programs[index].source);
  }
  final result = await Process.run('dart', ['analyze', '--format=machine', directory.path]);
  final errorsByFile = <String, List<String>>{};
  for (final line in '${result.stdout}\n${result.stderr}'.split('\n')) {
    final fields = line.split('|');
    if (fields.length < 8 || (fields.first != 'ERROR' && !_refusedWarnings.contains(fields[2]))) continue;
    errorsByFile.putIfAbsent(fields[3].split('/').last, () => []).add(fields[2]);
  }
  return errorsByFile;
}

void main() {
  late Directory directory;
  late Map<String, List<String>> errorsByFile;

  setUpAll(() async {
    directory = await Directory('tool/_public_surface').create();
    errorsByFile = await _analyzeEachProgram(directory);
  });

  tearDownAll(() async {
    await directory.delete(recursive: true);
  });

  group('a project that imports the barrel', () {
    for (var index = 0; index < _programs.length; index++) {
      final program = _programs[index];
      test('${program.compiles ? 'can write' : 'cannot write'} ${program.name}', () {
        final errors = errorsByFile['program_$index.dart'] ?? const <String>[];

        expect(errors.isEmpty, program.compiles, reason: 'analyzer errors: $errors');
      });
    }
  });
}
