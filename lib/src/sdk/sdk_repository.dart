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
/// [observesConnection].
///
/// A repository stands for one piece of data, not for a kind of data, so what
/// tells it which one is in its own fields, fixed when it is made. A project
/// writes one small class per piece of data it shows and makes one where a
/// screen needs it:
///
/// ```dart
/// final class AdultsList extends SdkRepository<List<User>, List<User>, UsersError, RestSignal> {
///   AdultsList(this._database, this._rest, {required this.minAge})
///     : super(offlineSignals: const {RestSignal.noRoute});
///
///   final OwnDatabase _database;
///   final RestUsers _rest;
///   final int minAge;
///
///   Rows<User> get _adults =>
///       _database.from(_database.users).where(_database.users.age.isGreaterThanOrEqualTo(minAge));
///
///   @override
///   bool get isAuthenticated => true;
///
///   @override
///   bool get observesConnection => true;
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
///   Future<List<User>?> initial() => _adults.select();
///
///   @override
///   Stream<List<User>> stream() => _adults.watch();
///
///   @override
///   UsersError resolve(Fault<RestSignal> fault) => switch (fault.signal) {
///     RestSignal.unauthorized => UsersError.signedOut,
///     _ => UsersError.unknown,
///   };
/// }
/// ```
///
/// [fetch], [response], [initial] and [stream] all read the same fields, so what
/// is asked of the network is exactly what is read from the database, and they
/// cannot drift apart. Write the query once and use it in both [initial] and
/// [stream]: were they to read different slices, [data] would change shape at
/// its first change. Two repositories with different parameters do not disturb
/// each other, and a refresh is only joined within one of them.
///
/// When a parameter changes while the screen is open, a search text or the next
/// page, make another repository and [dispose] the first. Nothing can be changed
/// in one that exists, so [data] never changes shape under a screen.
///
/// `R` is what [fetch] brings back, and it is the only thing that differs
/// between a REST call and a vendor's: [response] receives it. `T` is what the
/// screen reads, `E` the project's own error, and `S` the signal of the adapter
/// [fetch] fails with.
abstract base class SdkRepository<R, T, E, S extends Object> {
  /// A repository whose [data] is empty until it has read what the database holds.
  ///
  /// [offlineSignals] lists the signals that mean the network is out of reach. A
  /// [Fault] carrying one of them makes the refresh [StatusOffline] rather than
  /// [StatusFailed]. It is required and has no default: pylon cannot know which of
  /// an adapter's signals means the network rather than the server, and a project
  /// that has none says so with an empty set.
  SdkRepository({required Set<S> offlineSignals}) : _offlineSignals = offlineSignals;

  final MutableObservable<T?> _data = MutableObservable<T?>(null);
  final Set<S> _offlineSignals;
  final MutableObservable<Status<E>> _status = MutableObservable<Status<E>>(StatusRunning<E>());

  final List<StreamSubscription<bool>> _waiting = [];
  StreamSubscription<T>? _following;
  Future<Status<E>>? _running;
  bool _started = false;
  bool _disposed = false;

  /// Whether the request this makes carries the credential.
  ///
  /// When it does and `Credentials` holds none, a refresh makes no request and
  /// ends [StatusUnauthenticated]. A repository whose request signs someone in says `false`.
  bool get isAuthenticated;

  /// Whether a refresh looks at the connection before it asks.
  ///
  /// When it does and `Network` says the device is offline, no request is made
  /// and the refresh ends [StatusOffline]. When it does not, the request is
  /// always tried, and only its own failure says the network was out.
  ///
  /// It is the project's to say, and has no default, since it depends on what
  /// [fetch] talks to. A REST write says `false`: attempting it without a
  /// connection is worth a request, and a failure is the honest answer. A call to
  /// a vendor's own package, over bluetooth or a local network, needs no internet
  /// and says `false` too. A REST read that has nothing to bring back offline
  /// says `true`.
  bool get observesConnection;

  /// Asks the database for what it holds for this repository, once, and answers
  /// it.
  ///
  /// It is what [data] starts from, in place of a value the project would have
  /// to invent: it may hold something or nothing, and answers `null` for nothing
  /// when there is no such thing as an empty list of it. Called the first time
  /// [data] or [status] is read, while [status] is [StatusRunning].
  Future<T?> initial();

  /// The database's own stream for this repository: what it holds now, then every
  /// change to it.
  ///
  /// It is what [data] follows once [initial] has answered, and it is subscribed
  /// to once.
  Stream<T> stream();

  /// Asks the network, and only the network.
  ///
  /// Throws a [Fault] naming what went wrong, the contract every pylon operation
  /// holds. Anything else it throws is a bug and is left to propagate.
  Future<R> fetch();

  /// Writes what [fetch] brought back into the database, which is what moves
  /// [data].
  Future<void> response(R response);

  /// Turns the [Fault] a refresh failed with into the project's own error.
  ///
  /// Not called for a signal listed in `offlineSignals`.
  E resolve(Fault<S> fault);

  /// What the database holds, read with `data.value` and followed with
  /// `data.stream`, which gives a new listener the current value first.
  ///
  /// `null` until [initial] has answered, and after it when the database holds
  /// nothing. It follows the database a moment after a refresh completes, not
  /// before: it is `data.stream` that a screen follows.
  ///
  /// Reading it for the first time asks the database, which is why nothing
  /// touches it until a screen asks.
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
  /// while the repository [observesConnection] and the connection is out.
  ///
  /// Reading it for the first time starts loading [data], like [data] does.
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
    _release();
    await _following?.cancel();
    _following = null;
    await _data.dispose();
    await _status.dispose();
  }

  void _follow() {
    if (_started || _disposed) return;
    _started = true;
    unawaited(_load());
  }

  Future<void> _load() async {
    var read = true;
    try {
      _data.value = await initial();
    } catch (error, stackTrace) {
      read = false;
      _data.emitError(error, stackTrace);
    }
    if (_disposed) return;
    _following = stream().listen((stored) => _data.value = stored, onError: _data.emitError);
    if (_busy) return;
    if (read) {
      _announce(StatusSucceeded<E>());
    } else {
      _status.value = StatusIdle<E>();
    }
  }

  bool get _busy => _running != null || _holdsOffline;

  bool get _holdsOffline => _status.value is StatusOffline<E> && observesConnection;

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
    if (outcome is StatusOffline<E> && observesConnection) return _holdOffline(outcome);
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
    if (observesConnection && _isOffline) return StatusOffline<E>();

    try {
      await response(await fetch());
      return StatusSucceeded<E>();
    } on Fault<S> catch (fault) {
      if (_offlineSignals.contains(fault.signal)) return StatusOffline<E>();
      return StatusFailed<E>(resolve(fault));
    }
  }
}
