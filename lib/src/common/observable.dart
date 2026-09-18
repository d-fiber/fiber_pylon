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

/// A value that can be read now and watched for later changes.
///
/// Pylon hands these out for anything a caller both queries and follows: a
/// session, a health flag, a stored preference. Reading is synchronous so a
/// caller never has to wait for a first event, which is the failure mode of
/// exposing a bare [Stream].
abstract class Observable<T> {
  /// Allows subclasses to be const.
  const Observable();

  /// What this observable holds right now.
  T get value;

  /// Values published after the moment of subscription.
  ///
  /// The current [value] is not replayed. A listener that also needs it reads
  /// [value], or subscribes to [values] instead.
  Stream<T> get stream;

  /// The current [value], then everything [stream] publishes.
  Stream<T> get values => Stream<T>.multi((controller) {
    controller.add(value);
    final subscription = stream.listen(controller.add, onError: controller.addError, onDone: controller.close);
    controller.onCancel = subscription.cancel;
  });
}

/// An [Observable] whose holder can publish new values.
///
/// The writer keeps this reference and hands out the [Observable] view, so a
/// consumer that receives one cannot write to it.
class MutableObservable<T> extends Observable<T> {
  T _value;
  final StreamController<T> _controller = StreamController<T>.broadcast();

  /// Starts out holding [initial].
  MutableObservable(T initial) : _value = initial;

  @override
  T get value => _value;

  /// Publishes [next], unless it equals what is already held.
  ///
  /// Skipping equal values is what makes a health flag usable directly: a probe
  /// running every thirty seconds does not wake every listener when nothing has
  /// moved. Use [emit] for the rare case where the repetition is the signal.
  set value(T next) {
    if (next == _value) return;
    emit(next);
  }

  /// Publishes [next] even when it equals what is already held.
  void emit(T next) {
    _value = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  @override
  Stream<T> get stream => _controller.stream;

  /// Whether this observable has been disposed.
  bool get isClosed => _controller.isClosed;

  /// Closes [stream] for every listener.
  ///
  /// [value] stays readable afterwards: the last value a disposed observable
  /// held is still the truth about what happened, and callers routinely read it
  /// during teardown.
  Future<void> dispose() => _controller.close();
}
