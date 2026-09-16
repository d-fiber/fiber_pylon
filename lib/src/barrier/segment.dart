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

/// Splits [literal] into the segments an SDK author wrote by hand.
///
/// Every segment must be non-empty and never exactly `.` or `..`: a literal
/// comes from this SDK's own source, so a segment that could shift what a
/// composed chain resolves to is a defect in that source, not something to
/// route around silently.
List<String> literalSegments(String literal) => literal
    .split('/')
    .where((segment) => segment.isNotEmpty)
    .map(_rejectDotSegment)
    .toList();

/// The single, opaque segment [value] becomes.
///
/// Percent-encodes whatever [value] contains, so it can never introduce an
/// extra `/`, a `?`, or a `#` that would change how many segments a chain
/// carries or where its query string begins.
///
/// Encoding alone does not defend against a value that is exactly `.` or
/// `..`: neither character is reserved for [Uri.encodeComponent], so both
/// pass through unchanged, and a resolved path segment equal to either is
/// removed by dot-segment normalisation before a request ever reaches a
/// server — verified directly against `Uri.parse`, where `store/..`
/// resolves to the same segments as an empty path, dropping `store` with it.
/// This is rejected explicitly, for the same reason a literal `..` is
/// rejected in [literalSegments].
String opaqueSegment(Object value) {
  final text = '$value';
  if (text == '.' || text == '..') {
    throw ArgumentError.value(
      value,
      'value',
      'cannot be exactly "." or ".." once converted to a string: '
          'dot-segment normalisation would remove it, and the segment '
          'before it, from the resolved path',
    );
  }
  return Uri.encodeComponent(text);
}

String _rejectDotSegment(String segment) {
  if (segment == '.' || segment == '..') {
    throw ArgumentError.value(
      segment,
      'literal',
      'cannot contain a "." or ".." segment',
    );
  }
  return segment;
}
