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

    test('hands an error to every listener and keeps the value it held', () async {
      final observable = MutableObservable<int>(1);
      final errors = <Object>[];
      observable.stream.listen((_) {}, onError: errors.add);

      observable.emitError(StateError('the source failed'));
      await pumpEventQueue();

      expect(errors.single, isA<StateError>());
      expect(observable.value, 1);
      await observable.dispose();
    });

    test('hands no error once disposed', () async {
      final observable = MutableObservable<int>(1);
      await observable.dispose();

      observable.emitError(StateError('too late'));
    });

    test('holds what a followed source emits, and answers true once it began with a value', () async {
      final observable = MutableObservable<int?>(null);
      final source = StreamController<int?>();

      final began = observable.follow(source.stream);
      source.add(3);

      expect(await began, isTrue);
      await pumpEventQueue();
      expect(observable.value, 3);

      source.add(4);
      await pumpEventQueue();
      expect(observable.value, 4);
      await observable.dispose();
      await source.close();
    });

    test('answers true for a source that begins with nothing to hold', () async {
      final observable = MutableObservable<int?>(null);

      final began = observable.follow(Stream<int?>.value(null));

      expect(await began, isTrue);
      expect(observable.value, isNull);
      await observable.dispose();
    });

    test('hands the errors of a followed source to the listeners and answers false when it began with one', () async {
      final observable = MutableObservable<int?>(null);
      final errors = <Object>[];
      observable.stream.listen((_) {}, onError: errors.add);
      final source = StreamController<int?>();

      final began = observable.follow(source.stream);
      source.addError(StateError('the source failed'));

      expect(await began, isFalse);
      await pumpEventQueue();
      expect(errors.single, isA<StateError>());
      expect(observable.value, isNull);
      await observable.dispose();
      await source.close();
    });

    test('answers false for a source that ends without a word', () async {
      final observable = MutableObservable<int?>(null);

      expect(await observable.follow(const Stream<int?>.empty()), isFalse);
      await observable.dispose();
    });

    test('stops following the first source once it follows another', () async {
      final observable = MutableObservable<int?>(null);
      final first = StreamController<int?>();
      final second = StreamController<int?>();
      final began = observable.follow(first.stream);
      first.add(1);
      await began;

      observable.follow(second.stream);
      second.add(2);
      first.add(99);
      await pumpEventQueue();

      expect(observable.value, 2);
      expect(first.hasListener, isFalse);
      await observable.dispose();
      await first.close();
      await second.close();
    });

    test('stops following on request, keeps its value, and can follow again', () async {
      final observable = MutableObservable<int?>(null);
      final first = StreamController<int?>();
      final began = observable.follow(first.stream);
      first.add(1);
      await began;

      await observable.unfollow();
      first.add(99);
      await pumpEventQueue();

      expect(observable.value, 1);
      expect(first.hasListener, isFalse);

      expect(await observable.follow(Stream<int?>.value(5)), isTrue);
      await pumpEventQueue();
      expect(observable.value, 5);
      await observable.dispose();
      await first.close();
    });

    test('stops following once disposed, and follows nothing after', () async {
      final observable = MutableObservable<int?>(null);
      final source = StreamController<int?>();
      final began = observable.follow(source.stream);
      source.add(1);
      await began;

      await observable.dispose();

      expect(source.hasListener, isFalse);
      expect(await observable.follow(Stream<int?>.value(5)), isFalse);
      await source.close();
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
