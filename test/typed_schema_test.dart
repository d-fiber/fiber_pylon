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

import 'package:fiber_pylon/fiber_pylon.dart' hide Database;
import 'package:fiber_pylon/src/sdk/clients/local/database/engine/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

final class Author {
  const Author({this.id, required this.name});

  final int? id;
  final String name;
}

final class Authors extends KeyedTable<Author, int> {
  Authors() : super('authors');

  late final id = column.key();
  late final name = column.text('name').unique();

  @override
  List<Field<Object?>> get columns => [id, name];

  @override
  Author read(Reader row) => Author(id: row(id), name: row(name));

  @override
  List<Assignment> write(Author author) => [id.toOrGenerate(author.id), name.to(author.name)];
}

final class Book {
  const Book({this.id, required this.title, this.authorId, this.pages = 0});

  final int? id;
  final String title;
  final int? authorId;
  final int pages;
}

final class Books extends KeyedTable<Book, int> {
  Books() : super('books');

  late final id = column.key();
  late final title = column.text('title').collatedBy(Collation.noCase);
  late final authorId = column
      .integer('author_id')
      .references(Authors().id, onDelete: ReferentialAction.cascade)
      .nullable();
  late final pages = column.integer('pages').defaultsTo(0);

  @override
  List<Field<Object?>> get columns => [id, title, authorId, pages];

  @override
  List<List<Field<Object?>>> get indexes => [
    [title],
    [authorId, pages],
  ];

  @override
  Book read(Reader row) => Book(id: row(id), title: row(title), authorId: row(authorId), pages: row(pages));

  @override
  List<Assignment> write(Book book) => [
    id.toOrGenerate(book.id),
    title.to(book.title),
    authorId.to(book.authorId),
    pages.to(book.pages),
  ];
}

final class Reviews extends TypedTable<Author> {
  Reviews() : super('reviews');

  late final authorId = column
      .integer('author_id')
      .references(column.integer('id'), onDelete: ReferentialAction.setNull);

  @override
  List<Field<Object?>> get columns => [authorId];

  @override
  Author read(Reader row) => Author(id: row(authorId), name: '');

  @override
  List<Assignment> write(Author author) => [authorId.to(author.id!)];
}

void main() {
  late Directory directory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pylon_typed_schema');
    databaseFactoryFfi.setDatabasesPath(directory.path);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  group('LocalDatabase.declared', () {
    test('creates tables that differences reads as identical to their own declaration', () async {
      final authors = Authors();
      final books = Books();
      final db = LocalDatabase.declared(name: 'declared_same.db', tables: [authors, books]);
      await db.open();

      expect(await db.differences(authors.declaration), isEmpty);
      expect(await db.differences(books.declaration), isEmpty);
      await db.dispose();
    });

    test('reports a column added to a declared table as a difference the file no longer matches', () async {
      final authors = Authors();
      final db = LocalDatabase.declared(name: 'declared_drift.db', tables: [authors]);
      await db.open();
      await db.runSql('ALTER TABLE authors ADD COLUMN born INTEGER');

      final differences = await db.differences(authors.declaration);

      expect(differences.map((difference) => difference.kind), contains(DifferenceKind.unexpectedColumn));
      await db.dispose();
    });

    test('refuses a foreign key that points at a table it does not declare and closes the file', () async {
      final db = LocalDatabase.declared(name: 'declared_dangling.db', tables: [Books()]);

      await expectLater(
        db.open(),
        throwsA(isA<ArgumentError>().having((error) => error.message.toString(), 'message', contains('authors'))),
      );
      expect(db.isOpen, isFalse);
    });

    test('opens once the table a foreign key points at is declared too', () async {
      final db = LocalDatabase.declared(name: 'declared_resolved.db', tables: [Authors(), Books()]);

      await db.open();

      expect(db.isOpen, isTrue);
      await db.dispose();
    });

    test('refuses SET NULL on a column that refuses NULL and creates nothing', () async {
      final db = LocalDatabase.declared(name: 'declared_set_null.db', tables: [Authors(), Reviews()]);

      await expectLater(
        db.open(),
        throwsA(isA<ArgumentError>().having((error) => error.message.toString(), 'message', contains('SET NULL'))),
      );
      expect(db.isOpen, isFalse);
    });

    test('enforces the foreign keys it declares, since LocalDatabase turns them on for every connection', () async {
      final authors = Authors();
      final books = Books();
      final db = LocalDatabase.declared(name: 'declared_enforced.db', tables: [authors, books]);
      await db.open();
      final ada = await authors.on(db).insert(const Author(name: 'Ada'));
      await books.on(db).insert(Book(title: 'Notes', authorId: ada.id));

      await authors.on(db).remove(ada.id!);

      expect(await books.on(db).count(), 0);
      await db.dispose();
    });
  });
}
