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

import 'package:fiber_pylon/fiber_pylon.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher refusedWith(List<String> fragments) => throwsA(
  isA<ArgumentError>().having(
    (error) => error.message.toString(),
    'message',
    allOf([for (final fragment in fragments) contains(fragment)]),
  ),
);

DeclaredTable parents() => TableBuilder('parents').columns((c) => {'id': c.integer().isPrimary(), 'code': c.text()});

DeclaredTable pointingAt(String table, [String? column]) =>
    TableBuilder('child').columns((c) => {'p': c.integer().references(ColumnReference(table: table, column: column))});

void main() {
  group('DeclaredTable.checkTogether', () {
    test('accepts a foreign key onto a primary key, onto a unique column, onto a unique index and onto itself', () {
      final uniqueParents = TableBuilder('parents')
          .indexes(
            (i) => [
              i.name('parents_slug').columns(const [IndexColumn.named('slug')]).unique(),
            ],
          )
          .columns((c) => {'id': c.integer().isPrimary(), 'code': c.text().unique(), 'slug': c.text()});
      final children = TableBuilder('children')
          .foreignKeys(
            (fk) => [
              fk.columns(['by_code']).references('parents', ['code']),
              fk.columns(['by_slug']).references('PARENTS', ['SLUG']),
              fk.columns(['parent']).references('children'),
            ],
          )
          .columns(
            (c) => {
              'id': c.integer().isPrimary(),
              'parent': c.integer(),
              'by_code': c.text(),
              'by_slug': c.text(),
              'owner': c.integer().references(const ColumnReference(table: 'parents')),
            },
          );

      expect(() => DeclaredTable.checkTogether([uniqueParents, children]), returnsNormally);
    });

    test('accepts a composite key listed in another order than the parent declares it', () {
      final parent = TableBuilder(
        'pairs',
      ).primaryKey((pk) => pk.columns(['a', 'b'])).columns((c) => {'a': c.integer(), 'b': c.integer()});
      final child = TableBuilder('child')
          .foreignKeys(
            (fk) => [
              fk.columns(['x', 'y']).references('pairs', ['b', 'a']),
            ],
          )
          .columns((c) => {'x': c.integer(), 'y': c.integer()});

      expect(() => DeclaredTable.checkTogether([parent, child]), returnsNormally);
    });

    test('refuses a foreign key onto a table that is not declared', () {
      expect(
        () => DeclaredTable.checkTogether([pointingAt('nope')]),
        refusedWith(['Table "child", column "p" points at table "nope", which is not among the declared tables']),
      );
    });

    test('refuses a foreign key onto a column the parent does not declare', () {
      expect(
        () => DeclaredTable.checkTogether([parents(), pointingAt('parents', 'zz')]),
        refusedWith(['points at column "zz", which "parents" does not declare']),
      );
    });

    test('refuses a foreign key onto a column that is neither the primary key nor unique', () {
      expect(
        () => DeclaredTable.checkTogether([parents(), pointingAt('parents', 'code')]),
        refusedWith(['points at (code) of "parents", which is neither its primary key nor unique']),
      );
    });

    test('refuses a foreign key that names no column onto a parent with a key of another size', () {
      final pairs = TableBuilder(
        'pairs',
      ).primaryKey((pk) => pk.columns(['a', 'b'])).columns((c) => {'a': c.integer(), 'b': c.integer()});

      expect(
        () => DeclaredTable.checkTogether([pairs, pointingAt('pairs')]),
        refusedWith(['has 1 columns but "pairs" offers 2']),
      );
    });

    test('refuses a foreign key that names no column onto a parent with no primary key', () {
      final keyless = TableBuilder('keyless').columns((c) => {'x': c.integer()});

      expect(
        () => DeclaredTable.checkTogether([keyless, pointingAt('keyless')]),
        refusedWith(['points at "keyless" without naming columns, and "keyless" has no primary key']),
      );
    });

    test('refuses a partial unique index as the target of a foreign key', () {
      final partial = TableBuilder('p')
          .indexes(
            (i) => [
              i.name('p_a').columns(const [IndexColumn.named('a')]).unique().where('a > 0'),
            ],
          )
          .columns((c) => {'a': c.integer()});

      expect(
        () => DeclaredTable.checkTogether([partial, pointingAt('p', 'a')]),
        refusedWith(['neither its primary key nor unique']),
      );
    });

    test('lists every foreign key that cannot be resolved in one error', () {
      final second = TableBuilder(
        'second',
      ).columns((c) => {'p': c.integer().references(const ColumnReference(table: 'gone'))});

      expect(
        () => DeclaredTable.checkTogether([pointingAt('nope'), second]),
        refusedWith(['points at table "nope"', 'points at table "gone"']),
      );
    });
  });
}
