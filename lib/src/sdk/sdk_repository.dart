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

import '../common/fault.dart';
import '../common/health_monitor.dart';
import '../common/observable.dart';
import '../credential/credentials.dart';
import 'status.dart';

/// Where a screen reads one piece of data from: the local database, which this
/// brings up to date from the network.
///
/// The app never reads the network. It reads the local database, always, through
/// [value] and [stream], and a refresh only ever brings the database up to date:
/// [refresh] asks the network with [fetch], writes the answer with [response],
/// and the database's own [watchLocal] is what makes [stream] move. One way, so
/// the screen has no second source to reconcile with the first.
///
/// It reads like a `Preference`: [value], a call, [stream] and [values]. What
/// the last refresh did is a second one, [status], and it is independent: when a
/// refresh fails or the network is out, [value] is still what is stored, and
/// [status] says why it may not be up to date.
///
/// A repository carries its parameters in its own fields, so a project writes one
/// small class per piece of data it shows and makes one where it needs it:
///
/// ```dart
/// final class UsersList extends SdkRepository<List<User>, List<User>, UsersError, RestSignal> {
///   UsersList(this._database, this._rest)
///     : super(initial: const [], offlineSignals: const {RestSignal.noRoute});
///
///   final OwnDatabase _database;
///   final RestUsers _rest;
///
///   @override
///   bool get isAuthenticated => true;
///
///   @override
///   Future<List<User>> fetch() => _rest.list();
///
///   @override
///   Future<void> response(List<User> users) => _database.runTransaction((tx) async {
///     for (final user in users) {
///       await tx.from(_database.users).upsert(user);
///     }
///   });
///
///   @override
///   Stream<List<User>> watchLocal() => _database.from(_database.users).watch();
///
///   @override
///   UsersError resolve(Fault<RestSignal> fault) => switch (fault.signal) {
///     RestSignal.unauthorized => UsersError.signedOut,
///     _ => UsersError.unknown,
///   };
/// }
/// ```
///
/// `R` is what [fetch] brings back, and it is the only thing that differs
/// between a REST call and a vendor's: [response] receives it. `T` is what the
/// screen reads, `E` the project's own error, and `S` the signal of the adapter
/// [fetch] fails with.
abstract base class SdkRepository<R, T, E, S extends Object> extends Observable<T> {
  /// A repository reading as [initial] until the database has answered.
  ///
  /// [offlineSignals] lists the signals that mean the network is out of reach. A
  /// [Fault] carrying one of them makes the refresh [StatusOffline] rather than
  /// [StatusFailed]. It is required and has no default: pylon cannot know which of
  /// an adapter's signals means the network rather than the server, and a project
  /// that has none says so with an empty set.
  ///
  /// [health], when given, is consulted before a refresh, so a device known to be
  /// offline does not spend a request discovering what it already knows.
  SdkRepository({required T initial, required Set<S> offlineSignals, HealthMonitor? health})
    : _initial = initial,
      _offlineSignals = offlineSignals,
      _health = health;

  final T _initial;
  final Set<S> _offlineSignals;
  final HealthMonitor? _health;
  final _StatusObservable<E> _status = _StatusObservable<E>();

  BehaviorSubject<T>? _mirror;
  StreamSubscription<T>? _local;
  Future<Status<E>>? _running;
  bool _disposed = false;

  /// Whether the request this makes carries the credential.
  ///
  /// When it does and `Credentials` holds none, a refresh makes no request and
  /// ends [StatusUnauthenticated]. A repository whose request signs someone in says `false`.
  bool get isAuthenticated;

  /// What the database holds for this repository, and every change to it.
  ///
  /// The first thing it emits is what is stored now. It is what [value] follows,
  /// and it is subscribed to once, the first time [value] or [stream] is used.
  Stream<T> watchLocal();

  /// Asks the network, and only the network.
  ///
  /// Throws a [Fault] naming what went wrong, the contract every pylon operation
  /// holds. Anything else it throws is a bug and is left to propagate.
  Future<R> fetch();

  /// Writes what [fetch] brought back into the database, which is what moves
  /// [stream].
  Future<void> response(R response);

  /// Turns the [Fault] a refresh failed with into the project's own error.
  ///
  /// Not called for a signal listed in `offlineSignals`.
  E resolve(Fault<S> fault);

  /// What the database holds, or the initial value until it has answered.
  ///
  /// Follows the database a moment after a refresh completes, not before: it is
  /// [stream] that a screen follows.
  @override
  T get value => _follow.value;

  /// What the database holds, same as [value], so that `users()` reads as well
  /// as `users.value`.
  T call() => value;

  /// What the database holds for each new listener, followed by every change.
  @override
  Stream<T> get stream => _follow.stream;

  /// The value followed by every change, same as [stream].
  @override
  Stream<T> get values => stream;

  /// What the last refresh did, read with `status.value` and followed with
  /// `status.stream`.
  ///
  /// [StatusIdle] until a refresh has run.
  Observable<Status<E>> get status => _status;

  /// Brings the database up to date and answers how it went.
  ///
  /// A caller arriving while a refresh is under way waits on that same one, so
  /// six screens asking at once make one request. It never throws for a
  /// [Fault]: the status it returns is the outcome, and [status] carries the same.
  /// An error that is not a [Fault] is a bug: it propagates, and [status] goes
  /// back to [StatusIdle].
  Future<Status<E>> refresh() {
    if (_disposed) return Future<Status<E>>.value(_status.value);
    final running = _running;
    if (running != null) return running;

    final started = _run();
    _running = started;
    return started.whenComplete(() => _running = null);
  }

  /// Stops following the database and closes [stream] and [status].
  ///
  /// [value] stays readable, as what was last stored.
  Future<void> dispose() async {
    _disposed = true;
    await _local?.cancel();
    _local = null;
    await _mirror?.close();
    await _status.dispose();
  }

  BehaviorSubject<T> get _follow => _mirror ??= _open();

  BehaviorSubject<T> _open() {
    final subject = BehaviorSubject<T>.seeded(_initial);
    if (_disposed) {
      unawaited(subject.close());
      return subject;
    }
    _local = watchLocal().listen(subject.add, onError: subject.addError);
    return subject;
  }

  Future<Status<E>> _run() async {
    _status.publish(StatusRunning<E>());
    try {
      final outcome = await _attempt();
      _status.publish(outcome);
      return outcome;
    } catch (_) {
      _status.publish(StatusIdle<E>());
      rethrow;
    }
  }

  Future<Status<E>> _attempt() async {
    if (isAuthenticated && !Credentials.isHeld) return StatusUnauthenticated<E>();
    if (_health != null && !_health.isHealthy) return StatusOffline<E>();

    try {
      await response(await fetch());
      return StatusSucceeded<E>();
    } on Fault<S> catch (fault) {
      if (_offlineSignals.contains(fault.signal)) return StatusOffline<E>();
      return StatusFailed<E>(resolve(fault));
    }
  }
}

/// The [Observable] behind [SdkRepository.status].
final class _StatusObservable<E> extends Observable<Status<E>> {
  final BehaviorSubject<Status<E>> _subject = BehaviorSubject<Status<E>>.seeded(StatusIdle<E>());

  @override
  Status<E> get value => _subject.value;

  /// The current status, same as [value].
  Status<E> call() => _subject.value;

  @override
  Stream<Status<E>> get stream => _subject.stream;

  @override
  Stream<Status<E>> get values => stream;

  /// Publishes [next], unless it is the status already held.
  void publish(Status<E> next) {
    if (next == _subject.value || _subject.isClosed) return;
    _subject.add(next);
  }

  Future<void> dispose() => _subject.close();
}
