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
import 'package:flutter_test/flutter_test.dart';

enum ReadError { notFound, unknown }

void main() {
  group('Result', () {
    test('folds a success through the ok branch', () {
      const result = OK<int, ReadError>(3);

      expect(result.fold(ok: (data) => data * 2, failure: (_) => 0), 6);
    });

    test('folds a failure through the failure branch', () {
      const result = Failure<int, ReadError>(ReadError.notFound);

      expect(result.fold(ok: (data) => 'ok', failure: (error) => error.name), 'notFound');
    });

    test('map leaves a failure untouched', () {
      const result = Failure<int, ReadError>(ReadError.notFound);

      expect(result.map((data) => data * 2), const Failure<int, ReadError>(ReadError.notFound));
    });

    test('mapError converts an error into another vocabulary', () {
      const result = Failure<int, ReadError>(ReadError.notFound);

      expect(result.mapError((error) => error.name), const Failure<int, String>('notFound'));
    });

    test('orElse answers the fallback for a failure', () {
      const result = Failure<int, ReadError>(ReadError.unknown);

      expect(result.orElse(9), 9);
    });

    test('exposes the value and the error where they exist', () {
      const success = OK<int, ReadError>(3);
      const failure = Failure<int, ReadError>(ReadError.unknown);

      expect(success.dataOrNull, 3);
      expect(success.errorOrNull, isNull);
      expect(failure.dataOrNull, isNull);
      expect(failure.errorOrNull, ReadError.unknown);
    });
  });
}
