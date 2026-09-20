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
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final class _RestSdk extends RestSdkClient {
  @override
  Environments? get environments => null;
}

final class _LocalSdk extends LocalSdkClient {
  @override
  Environments? get environments => null;
}

final class _VendorSdk extends VendorSdkClient {
  @override
  Environments? get environments => null;
}

final class _MissingUrl extends Environments {
  const _MissingUrl();

  @override
  List<EnvironmentVariable> get variables => const [
    EnvironmentVariable(name: 'URL', value: null, reason: 'Where the API lives.'),
  ];
}

final class _RestSdkWithEnvironments extends RestSdkClient {
  @override
  Environments? get environments => const _MissingUrl();
}

final class _NeverInitializedClient extends RestSdkClient {
  @override
  Environments? get environments => null;
}

final class _TestSdk extends Sdk {
  var initializeCalls = 0;

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

final class _NeverInitializedSdk extends Sdk {}

final class _Api extends RestSdk {
  _Api() : this._([]);

  _Api._(this.reached)
    : super(
        RestClient(
          baseUrl: Uri.parse('https://house.test/v1/'),
          guard: CallGuard(),
          httpClient: MockClient((request) async {
            reached.add(request.url);
            return http.Response('{}', 200, headers: {'content-type': 'application/json'});
          }),
        ),
      );

  final List<Uri> reached;

  RestNode get users => RestNode(client).path((p) => p.segment('users'));

  @override
  Future<void> dispose() async {
    await client.dispose();
    await super.dispose();
  }
}

void main() {
  group('Sdk.instance', () {
    test('throws when nothing has registered yet', () {
      expect(
        () => Sdk.instance<_NeverInitializedSdk>(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('_NeverInitializedSdk().initialize()'),
          ),
        ),
      );
    });

    test('answers the instance initialize registered, without a project '
        'declaring anything for it', () async {
      final sdk = _TestSdk();
      await sdk.initialize();

      expect(Sdk.instance<_TestSdk>(), same(sdk));

      await sdk.dispose();
    });

    test('forgets the instance once disposed', () async {
      final sdk = _TestSdk();
      await sdk.initialize();
      await sdk.dispose();

      expect(() => Sdk.instance<_TestSdk>(), throwsStateError);
    });

    test(
      'keeps the newer instance registered when an older one, replaced '
      'without being disposed first, is disposed afterwards',
      () async {
        final first = _TestSdk();
        await first.initialize();

        final second = _TestSdk();
        await second.initialize();

        await first.dispose();

        expect(Sdk.instance<_TestSdk>(), same(second));

        await second.dispose();
      },
    );
  });

  group('RestSdk', () {
    test('sends the calls of a node made from its client through that client', () async {
      final api = _Api();
      await api.initialize();

      await api.users.get().send();

      expect(api.reached.single.toString(), 'https://house.test/v1/users');
      await api.dispose();
    });

    test('is reachable by its own type like any other Sdk', () async {
      final api = _Api();
      await api.initialize();

      expect(Sdk.instance<_Api>(), same(api));

      await api.dispose();
    });
  });

  group('RestSdkClient', () {
    test('answers rest for client without declaring it', () {
      final sdk = _RestSdk();

      expect(sdk.client, SdkClientKind.rest);
      expect(sdk, isA<SdkClient>());
    });
  });

  group('LocalSdkClient', () {
    test('answers local for client without declaring it', () {
      final sdk = _LocalSdk();

      expect(sdk.client, SdkClientKind.local);
      expect(sdk, isA<SdkClient>());
    });
  });

  group('VendorSdkClient', () {
    test('answers vendor for client without declaring it', () {
      final sdk = _VendorSdk();

      expect(sdk.client, SdkClientKind.vendor);
      expect(sdk, isA<SdkClient>());
    });
  });

  group('SdkClient.initialize', () {
    test('does nothing on a second call', () async {
      final sdk = _RestSdk();

      await sdk.initialize();
      await sdk.initialize();

      expect(sdk.isInitialized, isTrue);
    });

    test('throws an EnvironmentError naming everything missing', () async {
      final sdk = _RestSdkWithEnvironments();

      expect(
        sdk.initialize,
        throwsA(
          isA<EnvironmentError>()
              .having((error) => error.client, 'client', SdkClientKind.rest)
              .having((error) => error.missing.length, 'missing', 1),
        ),
      );
      expect(sdk.isInitialized, isFalse);
    });
  });

  group('SdkClient.instance', () {
    test('throws when nothing has registered yet', () {
      expect(
        () => SdkClient.instance<_NeverInitializedClient>(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('_NeverInitializedClient().initialize()'),
          ),
        ),
      );
    });

    test(
      'answers the instance initialize registered, without a project '
      'declaring anything for it',
      () async {
        final sdk = _RestSdk();
        await sdk.initialize();

        expect(SdkClient.instance<_RestSdk>(), same(sdk));

        await sdk.dispose();
      },
    );

    test('forgets the instance once disposed', () async {
      final sdk = _RestSdk();
      await sdk.initialize();
      await sdk.dispose();

      expect(() => SdkClient.instance<_RestSdk>(), throwsStateError);
    });

    test(
      'keeps the newer instance registered when an older one, replaced '
      'without being disposed first, is disposed afterwards',
      () async {
        final first = _RestSdk();
        await first.initialize();

        final second = _RestSdk();
        await second.initialize();

        await first.dispose();

        expect(SdkClient.instance<_RestSdk>(), same(second));

        await second.dispose();
      },
    );
  });
}
