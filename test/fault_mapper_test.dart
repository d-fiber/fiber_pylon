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

import 'package:flutter_test/flutter_test.dart';
import 'package:fiber_pylon/fiber_pylon.dart';

enum HouseSignal {
  unauthorized,
  forbidden,
  vpnRequired,
  nameEmpty,
  noRoute,
  teapot,
}

enum ForeignSignal { somethingElse }

enum CreateThing {
  unauthorized,
  notPermitted,
  vpnRequired,
  nameEmpty,
  networkError,
  unknown,
}

const createThing = FaultMapper<HouseSignal, CreateThing>(
  signals: {
    HouseSignal.unauthorized: CreateThing.unauthorized,
    HouseSignal.forbidden: CreateThing.notPermitted,
    HouseSignal.vpnRequired: CreateThing.vpnRequired,
    HouseSignal.nameEmpty: CreateThing.nameEmpty,
    HouseSignal.noRoute: CreateThing.networkError,
  },
  fallback: CreateThing.unknown,
);

void main() {
  group('FaultMapper', () {
    test('resolves a listed signal to the declared error', () {
      expect(
        createThing(const Fault(HouseSignal.forbidden)),
        CreateThing.notPermitted,
      );
    });

    test('resolves an unlisted signal to the fallback', () {
      expect(createThing(const Fault(HouseSignal.teapot)), CreateThing.unknown);
    });

    test('distinguishes two signals the backend refuses alike', () {
      expect(
        createThing(const Fault(HouseSignal.forbidden)),
        CreateThing.notPermitted,
      );
      expect(
        createThing(const Fault(HouseSignal.vpnRequired)),
        CreateThing.vpnRequired,
      );
    });

    test('resolves a signal without building a fault around it', () {
      expect(createThing.resolve(HouseSignal.nameEmpty), CreateThing.nameEmpty);
    });

    test('guard returns the value of an operation that succeeds', () async {
      final result = await createThing.guard(() async => 42);

      expect(result, const OK<int, CreateThing>(42));
    });

    test('guard maps a thrown fault through the table', () async {
      final result = await createThing.guard<int>(
        () async => throw const Fault(HouseSignal.noRoute),
      );

      expect(result, const Failure<int, CreateThing>(CreateThing.networkError));
    });

    test(
      'guard turns an exception that is not a fault into the fallback',
      () async {
        final result = await createThing.guard<int>(
          () async => throw const FormatException('leaked'),
        );

        expect(result, const Failure<int, CreateThing>(CreateThing.unknown));
      },
    );

    test('guard turns another vocabulary of fault into the fallback', () async {
      final result = await createThing.guard<int>(
        () async => throw const Fault(ForeignSignal.somethingElse),
      );

      expect(result, const Failure<int, CreateThing>(CreateThing.unknown));
    });
  });
}
