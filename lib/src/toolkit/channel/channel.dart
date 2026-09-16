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

/// Whether the live connection is usable right now.
///
/// Three states because three is what a reconnect policy needs, and they are
/// [ChannelKeeper]'s vocabulary rather than any backend's. An adapter maps its
/// own connection lifecycle onto them, and in doing so declares what the keeper
/// should do, which is worth knowing before choosing one.
enum ChannelState {
  /// Nothing is connected.
  ///
  /// The keeper reopens after a backoff delay, unless it was the one that asked
  /// for the close.
  closed,

  /// An attempt to connect is under way.
  ///
  /// The keeper waits and does nothing.
  opening,

  /// Events are flowing.
  ///
  /// The keeper resets its backoff and rejoins every recorded subscription, so
  /// an adapter must not publish this before joining is possible.
  open,
}

/// A live connection carrying events from named subscriptions.
///
/// The two things pylon assumes are the two every such backend has: a
/// subscription is identified by a name, and events arrive on a stream. What a
/// name means is the adapter's business, a topic for one backend and a
/// collection path for another, and `E` is whatever shape the events have in
/// this project. Pylon never reads either.
///
/// An implementation reports what happened rather than acting on it: it does not
/// reconnect on its own and does not remember what was subscribed. That is
/// [ChannelKeeper]'s job, and it is the same job whatever the backend.
abstract interface class Channel<E> {
  /// Events from every subscription currently joined.
  Stream<E> get events;

  /// Whether the connection is usable, published on every transition.
  Stream<ChannelState> get state;

  /// Opens the connection.
  Future<void> open();

  /// Closes the connection and every subscription with it.
  Future<void> close();

  /// Starts delivering events from the subscription called [name].
  Future<void> join(String name);

  /// Stops delivering events from the subscription called [name].
  Future<void> leave(String name);
}
