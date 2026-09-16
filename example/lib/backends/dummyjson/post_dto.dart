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

import 'package:equatable/equatable.dart';

import '../../contract/contract.dart';

/// A post in the shape DummyJSON sends it.
///
/// Note what is different from the other server: there is no author, there are
/// tags nobody upstream asked for, and the envelope around a list is named
/// `posts` rather than being the list itself. All of that dies here.
class DummyPost extends Equatable {
  /// The identifier, which arrives as a number.
  final int id;

  /// The headline.
  final String title;

  /// The text.
  final String body;

  /// Labels the server attaches, which the contract has no field for.
  final List<String> tags;

  /// Describes what the server sent.
  const DummyPost({
    required this.id,
    required this.title,
    required this.body,
    required this.tags,
  });

  /// Reads one post out of a decoded JSON object.
  factory DummyPost.fromJson(Map<String, dynamic> json) => DummyPost(
    id: (json['id'] as num).toInt(),
    title: json['title'] as String,
    body: json['body'] as String,
    tags: (json['tags'] as List<Object?>? ?? const [])
        .map((tag) => '$tag')
        .toList(),
  );

  /// This post as the contract knows a post.
  ///
  /// The tags become the author line, because the contract has somewhere to put
  /// them and this server has no author. A backend deciding how to fill the
  /// contract is exactly what an adapter is for.
  Post toContract() => Post(
    id: '$id',
    title: title,
    body: body,
    author: tags.isEmpty ? null : tags.join(', '),
  );

  @override
  List<Object?> get props => [id, title, body, tags];
}
