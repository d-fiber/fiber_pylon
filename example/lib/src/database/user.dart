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

import 'package:fiber_pylon/fiber_pylon.dart';

/// A stored user.
final class User {
  const User({required this.id, required this.name, required this.age, this.city});

  final String id;
  final String name;
  final int age;
  final String? city;
}

/// The table [User]s live in. It is declared once, and the project writes
/// every query with its columns — `usersTable.age.isGreaterThan(18)` — so a
/// misspelled name or a value of the wrong type does not compile.
final class UsersTable extends DatabaseKeyedTable<User, String> {
  UsersTable() : super('users');

  late final id = column.text('id').primaryKey();
  late final name = column.text('name');
  late final age = column.integer('age');
  late final city = column.text('city').nullable();

  /// Every account has users of its own, and never sees another's.
  @override
  Tunnel get tunnel => Tunnel.isolated;

  @override
  List<DatabaseField<Object?>> get columns => [id, name, age, city];

  @override
  List<List<DatabaseField<Object?>>> get indexes => [
    [age],
  ];

  @override
  User read(DatabaseReader row) => User(id: row(id), name: row(name), age: row(age), city: row(city));

  @override
  List<DatabaseAssignment> write(User user) => [
    id.to(user.id),
    name.to(user.name),
    age.to(user.age),
    city.to(user.city),
  ];
}
