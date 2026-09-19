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

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:meta/meta.dart';

import 'observable.dart';

/// Whether the network can be reached, from anywhere.
///
/// ```dart
/// Network.isReachable.value;                          // can it be?
/// Network.isReachable.stream.listen(showBanner);      // the answer now, then every change
/// ```
///
/// It is what the operating system says about the connection: a network
/// interface that is up, not a server that answers. A device on a wifi that
/// reaches nothing is reachable here, and a request over it fails on its own,
/// which is why a `SdkRepository` still lists the signals that mean the network
/// is out of reach. Pylon does not probe a host of its own choosing, since no
/// host is the right one for every project.
///
/// When the system cannot say, because the platform gives no answer or the
/// plugin is missing, it is reachable: nothing is ever refused on a guess.
///
/// Read before `configureSdk` returns, so nobody asks it a question it cannot
/// yet answer.
@Singleton()
class Network {
  Network._(this._reachable, this._changes);

  /// Whether the network can be reached, and its changes.
  final MutableObservable<bool> _reachable;

  /// What follows the operating system, `null` when there is nothing to follow.
  final StreamSubscription<bool>? _changes;

  /// Reads the connection the operating system reports, for `configureSdk`.
  ///
  /// Called by `configureSdk`, never by a project.
  @FactoryMethod(preResolve: true)
  static Future<Network> initialize() async {
    try {
      final connectivity = Connectivity();
      final first = reads(await connectivity.checkConnectivity());
      return _following(first, connectivity.onConnectivityChanged.map(reads));
    } catch (_) {
      return _following(true, const Stream<bool>.empty());
    }
  }

  /// A network that is [reachable] and changes as [changes] says, for a test.
  @visibleForTesting
  static Future<Network> forTesting({
    required bool reachable,
    Stream<bool> changes = const Stream<bool>.empty(),
  }) async => _following(reachable, changes);

  /// Whether [results], as the operating system reports them, mean a connection.
  ///
  /// None of them being `none` is enough, whatever the interface: a vpn, a
  /// bluetooth tether or a kind the platform cannot name may all reach the
  /// internet. An empty report is no connection.
  @visibleForTesting
  static bool reads(List<ConnectivityResult> results) =>
      results.isNotEmpty && results.any((result) => result != ConnectivityResult.none);

  static Network _following(bool initial, Stream<bool> changes) {
    final reachable = MutableObservable<bool>(initial);
    return Network._(reachable, changes.listen((next) => reachable.value = next, onError: (Object _) {}));
  }

  static Network get _instance => GetIt.instance<Network>();

  /// Whether the network can be reached, read with `isReachable.value` and
  /// followed with `isReachable.stream`, which gives a new listener the current
  /// answer first.
  static Observable<bool> get isReachable => _instance._reachable;

  /// Stops following the operating system and closes [isReachable], when
  /// `GetIt.reset` lets go of this singleton.
  @disposeMethod
  Future<void> dispose() async {
    await _changes?.cancel();
    await _reachable.dispose();
  }
}
