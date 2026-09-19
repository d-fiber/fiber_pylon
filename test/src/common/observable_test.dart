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

void main() {
  group('MutableObservable', () {
    test('holds the value it started with', () async {
      final observable = MutableObservable<int>(3);

      expect(observable.value, 3);
      await observable.dispose();
    });

    test('gives a new listener the current value, then every change', () async {
      final observable = MutableObservable<int>(1);
      observable.value = 2;
      final seen = <int>[];
      observable.stream.listen(seen.add);

      observable.value = 3;
      await pumpEventQueue();

      expect(seen, [2, 3]);
      await observable.dispose();
    });

    test('does not publish a value equal to the one it holds', () async {
      final observable = MutableObservable<int>(1);
      final seen = <int>[];
      observable.stream.skip(1).listen(seen.add);

      observable.value = 1;
      observable.value = 2;
      observable.value = 2;
      await pumpEventQueue();

      expect(seen, [2]);
      await observable.dispose();
    });

    test('publishes a value equal to the one it holds when told to emit it', () async {
      final observable = MutableObservable<int>(1);
      final seen = <int>[];
      observable.stream.skip(1).listen(seen.add);

      observable.emit(1);
      await pumpEventQueue();

      expect(seen, [1]);
      await observable.dispose();
    });

    test('keeps its last value readable once disposed, and publishes nothing more', () async {
      final observable = MutableObservable<int>(1);
      observable.value = 2;
      await observable.dispose();

      observable.value = 3;
      observable.emit(4);

      expect(observable.value, 2);
      expect(observable.isClosed, isTrue);
    });

    test('closes the streams it handed out', () async {
      final observable = MutableObservable<int>(1);
      final done = observable.stream.toList();

      await observable.dispose();

      expect(await done, [1]);
    });

    test('runs a listener before the value is set when it is synchronous', () async {
      final observable = MutableObservable<int>.synchronous(1);
      final seen = <int>[];
      observable.stream.listen(seen.add);
      await pumpEventQueue();
      seen.clear();

      observable.value = 2;

      expect(seen, [2]);
      await observable.dispose();
    });

    test('runs a listener in a later event when it is not synchronous', () async {
      final observable = MutableObservable<int>(1);
      final seen = <int>[];
      observable.stream.skip(1).listen(seen.add);

      observable.value = 2;

      expect(seen, isEmpty);
      await pumpEventQueue();
      expect(seen, [2]);
      await observable.dispose();
    });

    test('is handed out as an Observable that can only be read and followed', () async {
      final mutable = MutableObservable<int>(1);
      final Observable<int> view = mutable;

      mutable.value = 5;

      expect(view.value, 5);
      await mutable.dispose();
    });
  });
}
