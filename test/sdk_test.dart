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

import 'package:fiber_pylon/fiber_pylon.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class _RestSdk extends RestBackendSdk {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}
}

final class _LocalSdk extends LocalBackendSdk {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}
}

final class _VendorSdk extends VendorBackendSdk {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}
}

final class _AppPreferences extends ValkeryStorage {}

final class _SdkWithPreferences extends Sdk {
  var initializeCalls = 0;

  @override
  ValkeryStorage get preferences => _AppPreferences();

  @override
  Future<void> initialize() async {
    await super.initialize();
    initializeCalls++;
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ValkeryStorage.dispose();
  });

  group('Sdk.initialize', () {
    test('resolves preferences the first time it runs', () async {
      final sdk = _SdkWithPreferences();

      await sdk.initialize();

      expect(ValkeryStorage.isInitialized, isTrue);
      expect(ValkeryStorage.I, isA<_AppPreferences>());
    });

    test('does not try to resolve preferences again on a later call, the way a '
        'backend swap replays it', () async {
      final first = _SdkWithPreferences();
      await first.initialize();
      final resolved = ValkeryStorage.I;

      final second = _SdkWithPreferences();
      await second.initialize();

      expect(ValkeryStorage.I, same(resolved));
    });

    test(
      'leaves preferences untouched when an implementation needs none',
      () async {
        final sdk = _RestSdk();

        await sdk.initialize();

        expect(ValkeryStorage.isInitialized, isFalse);
      },
    );
  });

  group('Sdk.dispose', () {
    test(
      'forgets the resolved preferences so a later initialize resolves fresh ones',
      () async {
        final sdk = _SdkWithPreferences();
        await sdk.initialize();

        await sdk.dispose();

        expect(ValkeryStorage.isInitialized, isFalse);
      },
    );

    test(
      "leaves another implementation's resolved preferences intact when this "
      'one needs none',
      () async {
        final withPreferences = _SdkWithPreferences();
        await withPreferences.initialize();

        final withoutPreferences = _RestSdk();
        await withoutPreferences.dispose();

        expect(ValkeryStorage.isInitialized, isTrue);
      },
    );
  });

  group('RestBackendSdk', () {
    test('answers rest for type without declaring it', () {
      final sdk = _RestSdk();

      expect(sdk.type, SdkType.rest);
      expect(sdk, isA<BackendSdk>());
      expect(sdk, isA<SdkContract>());
    });
  });

  group('LocalBackendSdk', () {
    test('answers local for type without declaring it', () {
      final sdk = _LocalSdk();

      expect(sdk.type, SdkType.local);
      expect(sdk, isA<BackendSdk>());
      expect(sdk, isA<SdkContract>());
    });
  });

  group('VendorBackendSdk', () {
    test('answers vendor for type without declaring it', () {
      final sdk = _VendorSdk();

      expect(sdk.type, SdkType.vendor);
      expect(sdk, isA<BackendSdk>());
      expect(sdk, isA<SdkContract>());
    });
  });
}
