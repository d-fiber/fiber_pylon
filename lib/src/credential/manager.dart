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
import '../common/reporter.dart';
import 'credential.dart';
import 'refresher.dart';
import 'store.dart';

/// Keeps a credential alive, and is the reason a backend only has to write one
/// method.
///
/// This is the policy half of authentication, and it is the same policy whether
/// the credential comes from an HTTP endpoint, from Firebase, or from a fake in
/// a test. It renews ahead of expiry rather than after a call has already
/// failed, collapses simultaneous attempts into one exchange so a screen firing
/// six requests does not burn six refresh tokens, keeps a failed attempt pending
/// instead of dropping it, and revokes on the signals it was told mean the
/// credential is dead.
///
/// `C` is whatever the project calls its credential, and pylon never looks
/// inside it. Everything this needs to know is asked for explicitly:
/// [expiresAt] says where the expiry lives, [isRenewable] whether an exchange is
/// even possible, and [fatalSignals] which of the adapter's signals mean the
/// credential is gone. Nothing is read by convention, no shape is imposed on
/// `C`, and no failure is interpreted here.
///
/// A project with no notion of a credential never builds one of these. Nothing
/// else in pylon requires it.
///
/// [buffer] must be shorter than the lifetime of the credentials the backend
/// issues. When it is not, this renews at half of what a credential has left
/// rather than immediately, which keeps a misconfiguration slow instead of
/// turning it into a loop.
class CredentialManager<C extends Object, S extends Object> {
  final CredentialStore<C> _store;
  final CredentialRefresher<C> _refresher;
  final DateTime Function(C credential) _expiresAt;
  final bool Function(C credential) _isRenewable;
  final Set<S> _fatalSignals;
  final Duration _buffer;
  final Duration _retryDelay;
  final Reporter _reporter;

  final StreamController<CredentialChange<C>> _changes =
      StreamController<CredentialChange<C>>.broadcast();

  C? _current;
  Timer? _renewTimer;
  Timer? _retryTimer;
  Completer<void>? _inFlight;
  DateTime? _lastRenewal;
  bool _retryPending = false;
  bool _started = false;
  bool _disposed = false;

  /// Manages the credential kept in [store], renewed through [refresher].
  ///
  /// [expiresAt] reads the expiry out of a credential. A project whose
  /// credentials never expire passes a function returning a date far in the
  /// future, which is how it says so out loud rather than leaving it to be
  /// guessed.
  ///
  /// [fatalSignals] lists the signals that mean the credential is dead. One of
  /// them revokes it, which is what sends a holder back to a sign-in screen;
  /// anything else keeps it and schedules another attempt. It is required and
  /// has no default: pylon cannot know which of an adapter's signals means the
  /// credential was rejected rather than that the backend was unreachable, and
  /// getting it wrong is expensive in both directions. Too wide a set signs
  /// people out during an outage; too narrow a one leaves them retrying a
  /// credential that is gone.
  ///
  /// [isRenewable] answers whether an exchange can be attempted at all, for the
  /// credential that has no refresh half. It defaults to always, which is stated
  /// here rather than inferred from the credential.
  ///
  /// [buffer] is how long before expiry renewal starts, and [retryDelay] how
  /// long to wait after an attempt that failed for a reason that may pass.
  CredentialManager({
    required CredentialStore<C> store,
    required CredentialRefresher<C> refresher,
    required DateTime Function(C credential) expiresAt,
    required Set<S> fatalSignals,
    bool Function(C credential)? isRenewable,
    Duration buffer = const Duration(minutes: 10),
    Duration retryDelay = const Duration(seconds: 5),
    Reporter reporter = const SilentReporter(),
  }) : _store = store,
       _refresher = refresher,
       _expiresAt = expiresAt,
       _fatalSignals = fatalSignals,
       _isRenewable = isRenewable ?? _alwaysRenewable,
       _buffer = buffer,
       _retryDelay = retryDelay,
       _reporter = reporter;

  /// The credential in force, or `null` when there is none.
  C? get credential => _current;

  /// Whether a credential is in force.
  ///
  /// True for an expired credential that can still be renewed: it has not been
  /// revoked, so a screen must not send the holder back to a sign-in form.
  bool get isHeld => _current != null;

  /// Every transition of the credential, from the moment of subscription.
  ///
  /// [CredentialEvent.restored] is published by [start], so a listener attached
  /// before it runs learns what was found in storage.
  Stream<CredentialChange<C>> get changes => _changes.stream;

  /// How long before expiry renewal starts.
  Duration get buffer => _buffer;

  /// Whether the credential in force is within [buffer] of expiry, or past it.
  ///
  /// False when there is no credential at all: there is nothing stale about
  /// holding nothing.
  bool get isStale {
    final current = _current;
    if (current == null) return false;
    return !DateTime.now().isBefore(_expiresAt(current).subtract(_buffer));
  }

  /// Restores the stored credential and schedules its renewal.
  ///
  /// Publishes [CredentialEvent.restored] whether or not something was found.
  /// Calling this twice does nothing the second time.
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;

    final stored = await _store.read();
    _current = stored;
    _publish(CredentialEvent.restored, stored);

    if (stored == null) return;
    _schedule(stored);
  }

  /// Takes [credential] as the one in force and schedules its renewal.
  Future<void> grant(C credential) async {
    if (_disposed) return;
    _started = true;
    await _store.write(credential);
    _current = credential;
    _lastRenewal = DateTime.now();
    _publish(CredentialEvent.granted, credential);
    _schedule(credential);
  }

  /// Drops the credential and everything scheduled for it.
  ///
  /// Publishes [CredentialEvent.revoked] even when nothing was held, because a
  /// caller reacting to it wants the state, not the transition.
  Future<void> revoke() async {
    _cancelTimers();
    _retryPending = false;
    _lastRenewal = null;
    _current = null;
    await _store.clear();
    _publish(CredentialEvent.revoked, null);
  }

  /// Renews the credential when it is close enough to expiry to be worth it.
  ///
  /// Called before every authenticated request. Returns without doing anything
  /// in the common case, and when it does renew, concurrent callers all wait on
  /// the one exchange.
  ///
  /// This never throws. A renewal that fails for a temporary reason leaves the
  /// current credential in place and lets the request go out with it: it may well
  /// succeed, and if it does not, its own failure is the honest one to report.
  Future<void> ensureFresh() async {
    final current = _current;
    if (current == null || _disposed) return;
    if (!isStale) return;
    if (!_isExpired(current) && _renewedWithinCooldown) return;
    await _renew();
  }

  /// Renews the credential now, whatever its remaining lifetime.
  ///
  /// What a caller does after a request came back unauthorized. Like
  /// [ensureFresh] it never throws, and it collapses into any exchange already
  /// under way.
  Future<void> renew() async {
    if (_current == null || _disposed) return;
    await _renew();
  }

  /// Retries an attempt that was waiting for the network to come back.
  ///
  /// A host that watches connectivity calls this when it returns. Without it the
  /// pending attempt still runs, but only once [retryDelay] has elapsed again.
  void onConnectivityRestored() {
    if (!_retryPending || _disposed) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryPending = false;
    unawaited(_renew());
  }

  /// Stops every timer and closes [changes].
  ///
  /// The credential is left in storage: disposing is the app shutting down, not
  /// the holder signing out.
  Future<void> dispose() async {
    _disposed = true;
    _cancelTimers();
    await _changes.close();
  }

  bool _isExpired(C credential) =>
      !DateTime.now().isBefore(_expiresAt(credential));

  bool get _renewedWithinCooldown {
    final last = _lastRenewal;
    if (last == null) return false;
    return DateTime.now().difference(last) < _retryDelay;
  }

  void _publish(CredentialEvent event, C? credential) {
    if (_changes.isClosed) return;
    _changes.add(CredentialChange<C>(event, credential));
  }

  void _cancelTimers() {
    _renewTimer?.cancel();
    _renewTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _schedule(C credential) {
    _renewTimer?.cancel();
    if (_disposed) return;
    if (!_isRenewable(credential)) return;
    _renewTimer = Timer(_delayFor(credential), () => unawaited(_renew()));
  }

  Duration _delayFor(C credential) {
    final expiry = _expiresAt(credential);
    final now = DateTime.now();

    final ahead = expiry.subtract(_buffer).difference(now);
    if (ahead > Duration.zero) return ahead;

    final left = expiry.difference(now);
    if (left <= Duration.zero) return Duration.zero;
    return Duration(microseconds: left.inMicroseconds ~/ 2);
  }

  Future<void> _renew() {
    final active = _inFlight;
    if (active != null) return active.future;

    final completer = Completer<void>();
    _inFlight = completer;

    unawaited(
      _exchange().whenComplete(() {
        _inFlight = null;
        if (!completer.isCompleted) completer.complete();
      }),
    );

    return completer.future;
  }

  Future<void> _exchange() async {
    final current = _current;
    if (current == null || !_isRenewable(current)) return;

    try {
      final renewed = await _refresher.refresh(current);
      if (_disposed) return;

      _retryPending = false;
      _retryTimer?.cancel();
      _retryTimer = null;
      _lastRenewal = DateTime.now();

      await _store.write(renewed);
      _current = renewed;
      _publish(CredentialEvent.renewed, renewed);
      _schedule(renewed);
    } on Fault<S> catch (fault) {
      if (_disposed) return;
      if (_fatalSignals.contains(fault.signal)) {
        _reporter.log('Credential refused, revoking: $fault');
        await revoke();
        return;
      }
      _reporter.log('Credential renewal deferred: $fault');
      _bufferRetry();
    } catch (error, stackTrace) {
      if (_disposed) return;
      _reporter.recordError(
        error,
        stackTrace,
        context: {'operation': 'credential renewal'},
      );
      _bufferRetry();
    }
  }

  void _bufferRetry() {
    if (_disposed || _current == null) return;
    _retryPending = true;
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryDelay, () {
      _retryPending = false;
      unawaited(_renew());
    });
  }
}

bool _alwaysRenewable(Object credential) => true;
