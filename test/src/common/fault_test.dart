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

import 'dart:async';

import 'package:fiber_pylon/fiber_pylon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Fault', () {
    test('carries the status, details, cause and stack trace it was given', () {
      final cause = StateError('boom');
      final trace = StackTrace.current;

      final fault = Fault(status: 503, details: 'down', cause: cause, stackTrace: trace);

      expect(fault.status, 503);
      expect(fault.details, 'down');
      expect(fault.cause, same(cause));
      expect(fault.stackTrace, same(trace));
    });

    test('has no status, details, cause or stack trace unless given', () {
      const fault = Fault();

      expect(fault.status, isNull);
      expect(fault.details, isNull);
      expect(fault.cause, isNull);
      expect(fault.stackTrace, isNull);
    });

    test('is equal to a fault with the same status and details', () {
      expect(const Fault(status: 422, details: 'name'), const Fault(status: 422, details: 'name'));
      expect(const Fault(status: 409), const Fault(status: 409));
    });

    test('differs when the status, the details or the type of the cause differ', () {
      const base = Fault(status: 400, details: 'name');

      expect(base, isNot(const Fault(status: 422, details: 'name')));
      expect(base, isNot(const Fault(status: 400, details: 'email')));
      expect(base, isNot(const Fault(status: 400, details: 'name', cause: DuplicateCall())));
      expect(Fault(cause: StateError('one')), isNot(Fault(cause: ArgumentError('two'))));
    });

    test('ignores the stack trace and the message of the cause when comparing', () {
      final first = Fault(status: 500, cause: StateError('one'), stackTrace: StackTrace.current);
      final second = Fault(status: 500, cause: StateError('two'));

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('prints its status when it has one', () {
      expect(const Fault(status: 429).toString(), 'Fault(429)');
    });

    test('prints the type of its cause when it has no status', () {
      expect(Fault(cause: TimeoutException('late')).toString(), 'Fault(TimeoutException)');
      expect(const Fault(cause: DuplicateCall()).toString(), 'Fault(DuplicateCall)');
    });

    test('can be thrown and caught as an Exception', () {
      expect(() => throw const Fault(status: 403), throwsA(isA<Exception>()));
      expect(() => throw const Fault(status: 403), throwsA(const Fault(status: 403)));
    });
  });

  group('DuplicateCall', () {
    test('is an Exception', () {
      expect(const DuplicateCall(), isA<Exception>());
    });

    test('prints its name', () {
      expect(const DuplicateCall().toString(), 'DuplicateCall');
    });
  });
}
