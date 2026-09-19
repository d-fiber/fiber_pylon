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

part of 'database.dart';

/// Reads [read] now and again after every write to [table], answering each
/// result [same] does not call equal to the one before it.
///
/// Nothing runs until the stream is listened to, and it stops when the
/// listener cancels. A read that fails is an error event, not the end of the
/// stream: the next write reads again. A write that lands while a read is
/// running is not lost: the read is repeated once the running one is done.
Stream<T> _watchTable<T>(
  LocalDatabase database,
  String table,
  Future<T> Function() read,
  bool Function(T previous, T current) same, {
  bool followsTenant = false,
}) {
  late final StreamController<T> controller;
  StreamSubscription<Set<String>?>? subscription;
  StreamSubscription<String?>? tenantSubscription;
  var startOver = false;
  T? previous;
  var hasPrevious = false;
  var running = false;
  var dirty = false;

  Future<void> refresh() async {
    if (running) {
      dirty = true;
      return;
    }
    running = true;
    try {
      do {
        dirty = false;
        final tenant = Tenant.current;
        final current = await read();
        if (controller.isClosed) return;
        if (followsTenant && tenant != Tenant.current) {
          // the tenant changed while reading: what came back is not theirs
          startOver = dirty = true;
          continue;
        }
        if (startOver) hasPrevious = false;
        startOver = false;
        if (!hasPrevious || !same(previous as T, current)) controller.add(current);
        previous = current;
        hasPrevious = true;
      } while (dirty && !controller.isClosed);
    } catch (error, stackTrace) {
      if (!controller.isClosed) controller.addError(error, stackTrace);
    } finally {
      running = false;
    }
  }

  controller = StreamController<T>(
    onListen: () {
      subscription = database._writes.stream
          .where((written) => written == null || written.contains(table))
          .listen((_) => unawaited(refresh()));
      if (followsTenant) {
        tenantSubscription = Tenant.changes.listen((_) {
          startOver = true;
          unawaited(refresh());
        });
      }
      unawaited(refresh());
    },
    onCancel: () async {
      await subscription?.cancel();
      await tenantSubscription?.cancel();
    },
  );
  return controller.stream;
}

bool _sameRows(List<DatabaseRow> a, List<DatabaseRow> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final left = a[i];
    final right = b[i];
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) || right[entry.key] != entry.value) return false;
    }
  }
  return true;
}
