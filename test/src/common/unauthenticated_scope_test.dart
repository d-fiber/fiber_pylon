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

import 'package:fiber_pylon/src/common/unauthenticated_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('runUnauthenticated', () {
    test('is not in force outside it', () {
      expect(isUnauthenticated, isFalse);
    });

    test('is in force in the body and gives back what it produced', () async {
      final answer = await runUnauthenticated(() async => isUnauthenticated);

      expect(answer, isTrue);
    });

    test('stays in force after an await and in a call the body starts', () async {
      final seen = <bool>[];

      await runUnauthenticated(() async {
        await Future<void>.delayed(Duration.zero);
        seen.add(isUnauthenticated);
        await Future(() => seen.add(isUnauthenticated));
      });

      expect(seen, [true, true]);
    });

    test('ends with the body, and for whoever called it', () async {
      await runUnauthenticated(() async {});

      expect(isUnauthenticated, isFalse);
    });

    test('lets what the body throws through', () async {
      await expectLater(runUnauthenticated(() async => throw StateError('no')), throwsStateError);
      expect(isUnauthenticated, isFalse);
    });
  });
}
