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

import 'package:meta/meta.dart';

import '../common/fault.dart';
import '../common/network.dart';
import '../common/observable.dart';
import '../credential/credentials.dart';
import 'status.dart';

/// Where a screen reads one piece of data from: the local database, which this
/// brings up to date from the network.
///
/// The app never reads the network. It reads the local database, always, through
/// [data], and a refresh only ever brings the database up to date: [refresh]
/// asks the network with [fetch], writes the answer with [response], and the
/// database's own [stream] is what makes [data] move. One way, so the screen
/// has no second source to reconcile with the first.
///
/// [data] is an [Observable]: `data.value` and `data.stream`, the way a
/// `Preference` reads. What is happening to it is a second one, [status], and it
/// is independent: when a refresh fails or the network is out, [data] still
/// holds what is stored, and [status] says why it may not be up to date.
///
/// [status] is a signal more than a state. It starts as [StatusRunning], while
/// [data] loads what the database already holds, and every outcome is announced
/// once, to whoever follows it, and then it is [StatusIdle] again. Two states
/// do not let go at once: [StatusRunning] lasts until what it is doing is done,
/// and [StatusOffline] lasts until the connection is back, when the repository
/// [requiresConnection].
///
/// A repository that [isAuthenticated] listens to the database only while a
/// credential is held. It starts when someone signs in, and when they sign out it
/// stops listening and empties [data], without being disposed, so that it starts
/// again at the next sign-in. What a signed-out app would show is not what an
/// account stored.
///
/// A repository stands for one piece of data, not for a kind of data, so what
/// tells it which one is in its own fields, fixed when it is made. A project
/// writes one small class per piece of data it shows, with all its actions, and
/// makes one where a screen needs it. It listens to the database right after it
/// is made, so [data] already holds the stored value by the time a screen asks:
///
/// ```dart
/// final class AdultsList extends Repository<List<User>, List<User>, UsersError, RestSignal> {
///   AdultsList(this._database, this._rest, {required this.minAge});
///
///   final OwnDatabase _database;
///   final RestUsers _rest;
///   final int minAge;
///
///   Rows<User> get _adults =>
///       _database.from(_database.users).where(_database.users.age.isGreaterThanOrEqualTo(minAge));
///
///   @override
///   Future<List<User>> fetch() => _rest.list(minAge: minAge);
///
///   @override
///   Future<void> response(List<User> users) => _database.runTransaction((tx) async {
///     for (final user in users) {
///       await tx.from(_database.users).upsert(user);
///     }
///   });
///
///   @override
///   Stream<List<User>> stream() => _adults.stream();
///
///   @override
///   UsersError resolve(Fault<RestSignal> fault) => switch (fault.signal) {
///     RestSignal.unauthorized => UsersError.signedOut,
///     _ => UsersError.unknown,
///   };
/// }
/// ```
///
/// [fetch], [response] and [stream] all read the same fields, so what is asked of
/// the network is exactly what is read from the database, and they cannot drift
/// apart. Two repositories with different parameters do not disturb each other,
/// and a refresh is only joined within one of them.
///
/// When a parameter changes while the screen is open, a search text or the next
/// page, make another repository and [dispose] the first. Nothing can be changed
/// in one that exists, so [data] never changes shape under a screen.
///
/// `R` is what [fetch] brings back, and it is the only thing that differs
/// between a REST call and a vendor's: [response] receives it. `T` is what the
/// screen reads, `E` the project's own error, and `S` the signal of the adapter
/// [fetch] fails with.
abstract base class Repository<R, T, E, S extends Object> {
  /// A repository whose [data] is empty until the database has told what it holds,
  /// which it starts listening to right after it is made.
  Repository() {
    scheduleMicrotask(_follow);
  }

  final MutableObservable<T?> _data = MutableObservable<T?>(null);
  final MutableObservable<Status<E>> _status = MutableObservable<Status<E>>(StatusRunning<E>());

  final List<StreamSubscription<bool>> _waiting = [];
  StreamSubscription<bool>? _signedIn;
  Future<Status<E>>? _running;
  int _session = 0;
  bool _started = false;
  bool _disposed = false;

  /// Whether the request this makes carries the credential, and what it reads is
  /// an account's.
  ///
  /// When it does and `Credentials` holds none, a refresh makes no request and
  /// ends [StatusUnauthenticated], and the repository does not listen to the
  /// database: [data] is empty and [status] is [StatusIdle]. It listens once a
  /// credential is held, and when it is cleared it stops, empties [data] and
  /// ends any wait for the connection, without being disposed. A repository whose
  /// request signs someone in says `false`, and listens whatever is held.
  ///
  /// `true` unless a repository says otherwise, since what most of them read is an
  /// account's.
  bool get isAuthenticated => true;

  /// Whether a refresh needs the connection to be there before it asks.
  ///
  /// When it does and `Network` says the device is offline, no request is made
  /// and the refresh ends [StatusOffline]. When it does not, the request is
  /// always tried, and its own failure ends the refresh [StatusFailed].
  ///
  /// `true` unless a repository says otherwise, which is right for a REST read:
  /// with no connection there is nothing to ask. A REST write says `false`, since
  /// attempting it without a connection is worth a request and a failure is the
  /// honest answer. A call to a vendor's own package, over bluetooth or a local
  /// network, needs no internet and says `false` too.
  bool get requiresConnection => true;

  /// The database's own stream for this repository: what it holds now, first,
  /// then every change to it.
  ///
  /// The only way this repository reads the database, and the answer to what it
  /// listens to: it is subscribed to once, right after the repository is made,
  /// and each event becomes [data]. It emits `null` for nothing when there is no
  /// such thing as an empty list of it. Its first event is the stored value, so
  /// there is no separate initial value to give.
  Stream<T?> stream();

  /// Asks the network, and only the network.
  ///
  /// Throws a [Fault] naming what went wrong, the contract every pylon operation
  /// holds. Anything else it throws is a bug and is left to propagate.
  Future<R> fetch();

  /// Writes what [fetch] brought back into the database, which is what moves
  /// [data].
  Future<void> response(R response);

  /// Turns the [Fault] a refresh failed with into the project's own error, which
  /// is where a project says that a request that never reached the server means
  /// the network.
  E resolve(Fault<S> fault);

  /// What the database holds, read with `data.value` and followed with
  /// `data.stream`, which gives a new listener the current value first.
  ///
  /// `null` until the first event of [stream], and after it when the database
  /// holds nothing. It follows the database a moment after a refresh completes,
  /// not before: it is `data.stream` that a screen follows.
  ///
  /// The repository has been listening to the database since it was made, so a
  /// screen that asks later finds the stored value already here. One that asks
  /// within the first moments gets `null` first, then the value.
  ///
  /// Only there to be consumed: a subclass cannot override it, since the
  /// repository is what feeds it.
  @nonVirtual
  Observable<T?> get data {
    _follow();
    return _data;
  }

  /// What is happening to this repository, read with `status.value` and followed
  /// with `status.stream`.
  ///
  /// [StatusRunning] while [data] loads what the database holds, then that
  /// load is announced with [StatusSucceeded] and it is [StatusIdle]. Each
  /// refresh goes the same way: [StatusRunning] until it is done, then its
  /// outcome, then [StatusIdle]. The outcome is only there for whoever follows
  /// `status.stream` at the moment it is announced, and `status.value` is
  /// already [StatusIdle] by then. The exception is [StatusOffline], which stays
  /// while the repository [requiresConnection] and the connection is out.
  ///
  /// Starts loading [data] if it has not started, which it does on its own right
  /// after the repository is made.
  ///
  /// Only there to be consumed: a subclass cannot override it, since the
  /// repository is what moves it.
  @nonVirtual
  Observable<Status<E>> get status {
    _follow();
    return _status;
  }

  /// Brings the database up to date and answers how it went.
  ///
  /// A caller arriving while a refresh is under way waits on that same one, so
  /// six screens asking at once make one request. It never throws for a
  /// [Fault]: the status it returns is the outcome, which [status] announces to
  /// whoever follows it. While the repository is [StatusOffline] and the
  /// connection is still out it answers so at once, without a request and
  /// without moving [status]. An error that is not a [Fault] is a bug: it
  /// propagates, and [status] goes back to [StatusIdle].
  Future<Status<E>> refresh() {
    if (_disposed) return Future<Status<E>>.value(_status.value);
    _follow();
    final running = _running;
    if (running != null) return running;
    if (_holdsOffline && _isOffline) return Future<Status<E>>.value(_status.value);

    final started = _run();
    _running = started;
    return started.whenComplete(() => _running = null);
  }

  /// Stops following the database and closes [data] and [status].
  ///
  /// `data.value` stays readable, as what was last stored.
  Future<void> dispose() async {
    _disposed = true;
    _session++;
    _release();
    await _signedIn?.cancel();
    _signedIn = null;
    await _data.dispose();
    await _status.dispose();
  }

  void _follow() {
    if (_started || _disposed) return;
    _started = true;
    if (!isAuthenticated) {
      unawaited(_listen());
      return;
    }
    _signedIn = Credentials.held.stream.listen((held) => unawaited(held ? _listen() : _forget()));
  }

  Future<void> _listen() async {
    final session = ++_session;
    if (!_busy) _status.value = StatusRunning<E>();
    var read = false;
    try {
      read = await _data.follow(stream());
    } catch (error, stackTrace) {
      _data.emitError(error, stackTrace);
    }
    if (_disposed || session != _session || _busy) return;
    if (read) {
      _announce(StatusSucceeded<E>());
    } else {
      _status.value = StatusIdle<E>();
    }
  }

  Future<void> _forget() async {
    _session++;
    _release();
    await _data.unfollow();
    _data.value = null;
    if (_running == null) _status.value = StatusIdle<E>();
  }

  bool get _busy => _running != null || _holdsOffline;

  bool get _holdsOffline => _status.value is StatusOffline<E> && requiresConnection;

  bool get _isOffline => !Network.isReachable.value;

  Future<Status<E>> _run() async {
    _release();
    _status.value = StatusRunning<E>();
    try {
      final outcome = await _attempt();
      _conclude(outcome);
      return outcome;
    } catch (_) {
      _status.value = StatusIdle<E>();
      rethrow;
    }
  }

  void _conclude(Status<E> outcome) {
    if (outcome is StatusOffline<E>) return _holdOffline(outcome);
    _announce(outcome);
  }

  void _announce(Status<E> outcome) {
    _status.value = outcome;
    _status.value = StatusIdle<E>();
  }

  void _holdOffline(StatusOffline<E> outcome) {
    _status.value = outcome;
    _waiting.add(Network.isReachable.stream.skip(1).listen((_) => _reconsider()));
  }

  void _reconsider() {
    if (_isOffline) return;
    _release();
    _status.value = StatusIdle<E>();
  }

  void _release() {
    for (final waiting in _waiting) {
      unawaited(waiting.cancel());
    }
    _waiting.clear();
  }

  Future<Status<E>> _attempt() async {
    if (isAuthenticated && !Credentials.isHeld) return StatusUnauthenticated<E>();
    if (requiresConnection && _isOffline) return StatusOffline<E>();

    try {
      await response(await fetch());
      return StatusSucceeded<E>();
    } on Fault<S> catch (fault) {
      return StatusFailed<E>(resolve(fault));
    }
  }
}
