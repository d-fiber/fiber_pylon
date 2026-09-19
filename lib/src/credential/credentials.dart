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

import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:meta/meta.dart';

import '../common/fault.dart';
import '../common/observable.dart';
import '../common/reporter.dart';
import '../storage/secure_storage.dart';
import 'credential.dart';
import 'manager.dart';
import 'refresher.dart';
import 'store.dart';

/// The app's credential, from anywhere: whether there is one, what it is, and
/// when it is renewed.
///
/// Nothing else of the credential machinery is reachable. A project sets a
/// credential when someone signs in, clears it when they sign out, and asks:
///
/// ```dart
/// await Credentials.set(Credential(token: 'abc', refreshToken: 'r', expiresAt: expiry));
///
/// Credentials.isHeld;                       // is there one?
/// Credentials.value?.token;                 // what a call carries
/// Credentials.held.stream.listen(route);    // follow a sign-in and a sign-out
/// Credentials.stream.listen(reconnect);     // follow each credential, renewals too
///
/// await Credentials.clear();                // signing out
/// ```
///
/// It is kept in the operating system's vault and found again at the next
/// launch, before `configureSdk` returns, so nobody ever asks it a question it
/// cannot yet answer. A credential that carries a `refreshToken` and an
/// `expiresAt` is renewed ahead of expiry once the backend's exchange is
/// plugged in with [renewWith]; without it the credential is held and never
/// renewed.
///
/// `Tenant.follow` keeps the local database on the account the credential
/// names, and `CallGuard.renewing` renews for the calls a REST client makes.
@Singleton()
class Credentials {
  Credentials._(this._manager, this._exchange);

  /// The renewal policy and the credential it keeps.
  final CredentialManager<Credential, Object> _manager;

  /// What the backend supplies to renew, once [renewWith] has plugged it in.
  final _Exchange _exchange;

  /// The vault entry the credential is kept in.
  static const String _entry = 'pylon.credential.v1';

  /// Restores the credential kept in the vault, for `configureSdk`.
  ///
  /// Called by `configureSdk`, never by a project.
  @FactoryMethod(preResolve: true)
  static Future<Credentials> initialize(SecureStorage secure) => _restore(
    StoredCredential<Credential>(
      secure.packageString(_entry),
      encode: (credential) => credential.encode(),
      decode: Credential.decode,
    ),
  );

  /// Credentials over [store] instead of the vault, for a test.
  @visibleForTesting
  static Future<Credentials> forTesting(CredentialStore<Credential> store, {Reporter? reporter}) =>
      _restore(store, reporter: reporter ?? const SilentReporter());

  static Future<Credentials> _restore(
    CredentialStore<Credential> store, {
    Reporter reporter = const SilentReporter(),
  }) async {
    final exchange = _Exchange();
    final manager = CredentialManager<Credential, Object>(
      store: store,
      refresher: exchange,
      expiresAt: _expiryOf,
      fatalSignals: exchange.fatalSignals,
      isRenewable: exchange.canRenew,
      reporter: reporter,
    );
    await manager.start();
    return Credentials._(manager, exchange);
  }

  /// When [credential] stops being accepted, which for one that never does is
  /// far enough away that nothing is ever scheduled for it.
  static DateTime _expiryOf(Credential credential) => credential.expiresAt ?? DateTime.utc(9999);

  static Credentials get _instance => GetIt.instance<Credentials>();

  /// The credential in force, or `null` when there is none.
  static Credential? get value => _instance._manager.value;

  /// Whether a credential is in force.
  ///
  /// True for an expired credential that can still be renewed: it has not been
  /// revoked, so a screen must not send the holder back to a sign-in form.
  static bool get isHeld => _instance._manager.isHeld;

  /// [isHeld], read with `held.value` and followed with `held.stream`.
  ///
  /// A renewal does not move it, so following it wakes a listener only when
  /// someone signs in or out.
  static Observable<bool> get held => _instance._manager.held;

  /// The credential in force for each new listener, followed by every one that
  /// replaces it: a sign-in, a renewal, and `null` on a sign-out.
  ///
  /// A listener has run before [set], [clear] or the renewal that caused the
  /// change returns.
  static Stream<Credential?> get stream => _instance._manager.stream;

  /// The credential in force followed by every change, same as [stream].
  static Stream<Credential?> get values => stream;

  /// Whether the credential in force is within a few minutes of expiry, or past
  /// it, which is when a renewal is due.
  ///
  /// False when there is no credential at all.
  static bool get isStale => _instance._manager.isStale;

  /// Takes [credential] as the one in force, keeps it in the vault, and schedules
  /// its renewal.
  ///
  /// Throws when the vault refuses, and the credential in force is left as it was.
  static Future<void> set(Credential credential) => _instance._manager.grant(credential);

  /// Drops the credential, from the vault as well, and everything scheduled for
  /// it. What signing out comes down to.
  static Future<void> clear() => _instance._manager.revoke();

  /// Plugs in the backend's exchange, which is what makes a credential that has
  /// a `refreshToken` and an `expiresAt` renew itself.
  ///
  /// [refresh] turns the credential in force into a fresh one. It throws a
  /// [Fault] naming what went wrong, and nothing else about renewal is left to
  /// it: when to renew, joining simultaneous attempts into one exchange, trying
  /// again and giving up are all decided here.
  ///
  /// [fatalSignals] lists the signals that mean the credential is dead. One of
  /// them clears it, which is what sends a holder back to a sign-in screen;
  /// anything else keeps it and tries again. It is required and has no default:
  /// pylon cannot know which of an adapter's signals means the credential was
  /// rejected rather than that the backend was unreachable, and getting it wrong
  /// is expensive in both directions. Too wide a set signs people out during an
  /// outage; too narrow a one leaves them retrying a credential that is gone.
  ///
  /// Calling it again replaces the exchange. Best called once, right after
  /// `configureSdk`, so that a credential restored from the vault is renewed at
  /// once when it went stale while the app was closed.
  static void renewWith<S extends Object>({
    required Future<Credential> Function(Credential current) refresh,
    required Set<S> fatalSignals,
  }) {
    final instance = _instance;
    instance._exchange.plug(refresh, fatalSignals);
    instance._manager.rearm();
  }

  /// Renews the credential now, whatever its remaining lifetime, and never
  /// throws.
  ///
  /// What a caller does after a request came back unauthorized outside of a
  /// `CallGuard`. It joins any exchange already under way.
  static Future<void> renew() => _instance._manager.renew();

  /// Retries a renewal that was waiting for the network to come back.
  ///
  /// A host that watches connectivity calls this when it returns.
  static void onConnectivityRestored() => _instance._manager.onConnectivityRestored();

  /// Renews the credential when it is close enough to expiry to be worth it,
  /// for `CallGuard` to call before every authenticated request.
  @internal
  static Future<void> ensureFresh() => _instance._manager.ensureFresh();

  /// Stops every timer and closes the streams, when `GetIt.reset` lets go of this
  /// singleton.
  ///
  /// The credential stays in the vault: this is the app shutting down, not the
  /// holder signing out.
  @disposeMethod
  Future<void> dispose() => _manager.dispose();
}

/// The backend's exchange and the signals that mean a credential is dead, filled
/// in after the manager that reads them is built.
final class _Exchange implements CredentialRefresher<Credential> {
  Future<Credential> Function(Credential current)? _refresh;

  /// Shared with the manager, which reads it at every failure.
  final Set<Object> fatalSignals = <Object>{};

  /// Replaces the exchange and the signals with [refresh] and [signals].
  void plug(Future<Credential> Function(Credential current) refresh, Set<Object> signals) {
    _refresh = refresh;
    fatalSignals
      ..clear()
      ..addAll(signals);
  }

  /// Whether [credential] can be exchanged: the backend has said how, and the
  /// credential carries what it takes.
  bool canRenew(Credential credential) => _refresh != null && credential.refreshToken != null;

  @override
  Future<Credential> refresh(Credential current) => _refresh!(current);
}
