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

import 'package:rxdart/rxdart.dart';

/// A value that can be read now and followed for changes.
///
/// Pylon hands these out for anything a caller both queries and follows, such as
/// a session, a health flag or a stored preference. Reading is immediate, so
/// nobody waits for a first event as they would with a bare [Stream].
abstract class Observable<T> {
  /// Allows subclasses to be const.
  const Observable();

  /// What this observable holds right now.
  T get value;

  /// The current [value] for each new listener, followed by every change.
  ///
  /// A listener never has to read [value] as well to know where things stand.
  Stream<T> get stream;
}

/// An [Observable] whose holder can publish new values.
///
/// The writer keeps this reference and hands out the [Observable] view, so a
/// consumer that receives one cannot write to it.
class MutableObservable<T> extends Observable<T> {
  /// Starts out holding [initial]. Listeners are notified in a later event, not
  /// during the publishing call.
  MutableObservable(T initial) : _subject = BehaviorSubject<T>.seeded(initial);

  /// Starts out holding [initial]. Listeners are notified before the publishing
  /// call returns, for a change that must be in place before anyone can ask.
  ///
  /// A listener must not publish again while it runs.
  MutableObservable.synchronous(T initial) : _subject = BehaviorSubject<T>.seeded(initial, sync: true);

  /// The current value and its changes.
  final BehaviorSubject<T> _subject;
  StreamSubscription<T>? _source;

  @override
  T get value => _subject.value;

  /// Publishes [next], unless it equals what is already held.
  ///
  /// Skipping equal values is what makes a health flag usable directly: a probe
  /// running every thirty seconds does not wake every listener when nothing has
  /// moved. Use [emit] for the rare case where the repetition is the signal.
  set value(T next) {
    if (next == _subject.value) return;
    emit(next);
  }

  /// Publishes [next] even when it equals what is already held.
  ///
  /// Does nothing once this has been disposed.
  void emit(T next) {
    if (_subject.isClosed) return;
    _subject.add(next);
  }

  /// Hands [error] to every listener instead of a value, and keeps [value] as it
  /// was.
  ///
  /// Does nothing once this has been disposed.
  void emitError(Object error, [StackTrace? stackTrace]) {
    if (_subject.isClosed) return;
    _subject.addError(error, stackTrace);
  }

  /// Holds what [source] emits: every event becomes [value], and every error goes
  /// to the listeners through [emitError].
  ///
  /// Answers once, as soon as [source] has said something: `true` when it began
  /// with a value, `false` when it began with an error or ended without a word. A
  /// source that never says anything never answers, so [source] is one that
  /// starts with what it holds now.
  ///
  /// Following another source stops following the first, and [dispose] stops
  /// following. Answers `false` at once when this has been disposed.
  Future<bool> follow(Stream<T> source) {
    if (_subject.isClosed) return Future<bool>.value(false);
    final first = Completer<bool>();
    unawaited(_source?.cancel());
    _source = source.listen(
      (event) {
        value = event;
        if (!first.isCompleted) first.complete(true);
      },
      onError: (Object error, StackTrace stackTrace) {
        emitError(error, stackTrace);
        if (!first.isCompleted) first.complete(false);
      },
      onDone: () {
        if (!first.isCompleted) first.complete(false);
      },
    );
    return first.future;
  }

  /// Stops following its source and keeps [value] as it is, so that it can follow
  /// again later. Emptying it is up to the owner, with `value =`.
  Future<void> unfollow() async {
    await _source?.cancel();
    _source = null;
  }

  @override
  Stream<T> get stream => _subject.stream;

  /// Whether this observable has been disposed.
  bool get isClosed => _subject.isClosed;

  /// Stops following its source and closes [stream] for every listener.
  ///
  /// [value] stays readable afterwards: the last value a disposed observable
  /// held is still the truth about what happened, and callers routinely read it
  /// during teardown.
  Future<void> dispose() async {
    await _source?.cancel();
    _source = null;
    await _subject.close();
  }
}
