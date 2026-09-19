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

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _prelude = '''
import 'package:fiber_pylon/src/sdk/clients/local/database/engine/database.dart';
import 'package:fiber_pylon/src/sdk/clients/local/database/engine/schema/schema.dart';

final class Todo implements Storable {
  const Todo();

  @override
  RawRow toRow() => {'title': Value.varchar('a')};
}

Future<void> program(LocalDatabase db) async {
''';

final class _Program {
  const _Program(this.name, this.body, {required this.compiles});

  final String name;
  final String body;
  final bool compiles;

  String get source => '$_prelude$body\n}\n';
}

const _programs = [
  _Program('a table declaration assembled by hand', "const DeclaredTable(name: 't', columns: {});", compiles: false),
  _Program(
    'a column definition assembled by hand',
    'const ColumnDefinition(type: ColumnType.text, notNull: false, isPrimary: false, unique: false, autoincrement: true);',
    compiles: false,
  ),
  _Program(
    'a foreign key assembled by hand',
    "const TableForeignKey(columns: ['a', 'b'], referencedTable: 'x', referencedColumns: ['id']);",
    compiles: false,
  ),
  _Program('a primary key assembled by hand', 'const PrimaryKeyConstraint(columns: []);', compiles: false),
  _Program('an index assembled by hand', "const TableIndex(name: 'i', columns: []);", compiles: false),
  _Program('a unique constraint assembled by hand', 'const UniqueConstraint(columns: []);', compiles: false),
  _Program('a check assembled by hand', "const CheckConstraint(expression: '');", compiles: false),
  _Program(
    'an any column in a table SQLite does not type-check',
    "TableBuilder('t').columns((c) => {'a': c.any()});",
    compiles: false,
  ),
  _Program(
    'an any column opened by a strict column factory built by hand',
    "TableBuilder('t').columns((c) => {'a': const StrictColumnFactory().any()});",
    compiles: false,
  ),
  _Program(
    'an any column in a strict table',
    "TableBuilder('t').strict().columns((c) => {'a': c.any()});",
    compiles: true,
  ),
  _Program(
    'an any column in a table made strict after another option',
    "TableBuilder('t').withoutRowid().strict().columns((c) => {'a': c.any()});",
    compiles: true,
  ),
  _Program('a strict table asked to be strict again', "TableBuilder('t').strict().strict();", compiles: false),
];

Future<Map<String, List<String>>> _analyzeEachProgram(Directory directory) async {
  for (var index = 0; index < _programs.length; index++) {
    await File('${directory.path}/program_$index.dart').writeAsString(_programs[index].source);
  }
  final result = await Process.run('dart', ['analyze', '--format=machine', directory.path]);
  final errorsByFile = <String, List<String>>{};
  for (final line in '${result.stdout}\n${result.stderr}'.split('\n')) {
    final fields = line.split('|');
    if (fields.length < 8 || fields.first != 'ERROR') continue;
    errorsByFile.putIfAbsent(fields[3].split('/').last, () => []).add(fields[2]);
  }
  return errorsByFile;
}

void main() {
  late Directory directory;
  late Map<String, List<String>> errorsByFile;

  setUpAll(() async {
    directory = await Directory('test/_compile_refusals').create();
    errorsByFile = await _analyzeEachProgram(directory);
  });

  tearDownAll(() async {
    await directory.delete(recursive: true);
  });

  group('the analyzer', () {
    for (var index = 0; index < _programs.length; index++) {
      final program = _programs[index];
      test('${program.compiles ? 'accepts' : 'refuses'} ${program.name}', () {
        final errors = errorsByFile['program_$index.dart'] ?? const <String>[];

        expect(errors.isEmpty, program.compiles, reason: 'analyzer errors: $errors');
      });
    }
  });
}
