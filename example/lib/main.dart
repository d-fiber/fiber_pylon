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

import 'package:flutter/material.dart';

import 'backends/dummyjson/dummy_backend.dart';
import 'backends/memory/memory_backend.dart';
import 'backends/placeholder/placeholder_backend.dart';
import 'contract/contract.dart';
import 'ui/posts_page.dart';

/// Every backend this app can put behind the contract.
///
/// This map is the whole of the swap. Adding a fourth server means writing an
/// adapter and one line here, and the screen does not move.
final Map<String, ExampleBackend Function()> backends = {
  'memory': MemoryBackend.new,
  'jsonplaceholder': PlaceholderBackend.new,
  'dummyjson': DummyBackend.new,
};

void main() => runApp(const ExampleApp());

/// The example app.
class ExampleApp extends StatefulWidget {
  /// Creates the app.
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  ExampleBackend? _backend;

  @override
  void initState() {
    super.initState();
    _plug('memory');
  }

  @override
  void dispose() {
    _backend?.dispose();
    super.dispose();
  }

  Future<void> _plug(String name) async {
    final previous = _backend;
    setState(() => _backend = null);

    final next = backends[name]!();
    await next.initialize();
    await previous?.dispose();

    if (!mounted) {
      await next.dispose();
      return;
    }
    setState(() => _backend = next);
  }

  @override
  Widget build(BuildContext context) {
    final backend = _backend;

    return MaterialApp(
      title: 'pylon',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: backend == null
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : PostsPage(
              backend: backend,
              choices: backends.keys.toList(),
              onSwitch: _plug,
            ),
    );
  }
}
