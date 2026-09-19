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
import 'package:fiber_pylon/src/credential/credential.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Credential', () {
    test('reads back what it was written as', () {
      final credential = Credential(
        token: 'abc',
        refreshToken: 'again',
        expiresAt: DateTime.utc(2027, 1, 2, 3, 4, 5),
        holder: 'ada',
      );

      expect(Credential.decode(credential.encode()), credential);
    });

    test('reads back a credential that has only a token', () {
      const credential = Credential(token: 'abc');

      final read = Credential.decode(credential.encode());

      expect(read, credential);
      expect(read.refreshToken, isNull);
      expect(read.expiresAt, isNull);
      expect(read.holder, isNull);
    });

    test('keeps the instant of an expiry given in local time', () {
      final expiry = DateTime.now().add(const Duration(hours: 3));

      final read = Credential.decode(Credential(token: 'abc', expiresAt: expiry).encode());

      expect(read.expiresAt!.isAtSameMomentAs(expiry), isTrue);
    });

    test('refuses what is not a credential, without repeating it', () {
      for (final raw in ['secret-token', '[1, 2]', '{"refreshToken": "secret-refresh"}', '{"token": 3}']) {
        expect(
          () => Credential.decode(raw),
          throwsA(
            isA<FormatException>()
                .having((error) => error.message, 'message', isNot(contains('secret')))
                .having((error) => error.source, 'source', isNull),
          ),
          reason: raw,
        );
      }
    });

    test('never shows its tokens when printed', () {
      const credential = Credential(token: 'secret-token', refreshToken: 'secret-refresh');

      expect('$credential', isNot(contains('secret')));
    });

    test('is equal to the same credential whose expiry is written in another zone', () {
      final local = DateTime.now().add(const Duration(hours: 1));

      expect(Credential(token: 'abc', expiresAt: local), Credential(token: 'abc', expiresAt: local.toUtc()));
    });

    test('is equal to another that holds the same things', () {
      const a = Credential(token: 'abc', holder: 'ada');
      const b = Credential(token: 'abc', holder: 'ada');

      expect(a, b);
      expect(a, isNot(const Credential(token: 'abc', holder: 'bob')));
    });
  });
}
