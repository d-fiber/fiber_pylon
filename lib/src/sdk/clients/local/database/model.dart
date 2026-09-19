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

/// A project's own type stored in a [Collection].
///
/// ```dart
/// final class User implements Model {
///   const User({required this.id, required this.name});
///   @override
///   final String id;
///   final String name;
///
///   factory User.fromJson(String id, Map<String, Object?> json) => User(id: id, name: json['name'] as String);
///
///   @override
///   Map<String, Object?> toJson() => {'name': name};
/// }
/// ```
///
/// The id is the document's own key, kept apart from its fields: [toJson]
/// leaves it out, and the `fromJson` a [Collection] is given receives it as
/// its own argument.
abstract interface class Model {
  /// This document's key in its [Collection]. Empty on a document that does
  /// not have one yet: [Collection.add] then assigns one.
  String get id;

  /// This document's fields, as JSON.
  ///
  /// May hold a [DateTime] (stored as its UTC ISO-8601 text, which compares
  /// in time order), an [Enum] (stored by name), or a nested [Model], on top
  /// of JSON's own types, and a [FieldValue] anywhere in it. Anything else fails the write with an
  /// [ArgumentError] naming the model.
  Map<String, Object?> toJson();
}
