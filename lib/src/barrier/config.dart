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

import 'package:equatable/equatable.dart';

/// One value a backend cannot start without.
class Requirement extends Equatable {
  /// What the value is called where it is set, so the message names something
  /// that can actually be searched for.
  final String name;

  /// The value as it was found, `null` or empty when it was not.
  final String? value;

  /// What the backend needs it for, in one short sentence.
  ///
  /// This is what someone reads when they hit the error, usually without having
  /// ever seen the backend's source.
  final String purpose;

  /// Declares that [name] is needed, for [purpose], and was found to be [value].
  const Requirement({
    required this.name,
    required this.value,
    required this.purpose,
  });

  /// Whether a usable value was found.
  bool get isSatisfied => value != null && value!.isNotEmpty;

  @override
  List<Object?> get props => [name, value, purpose];
}

/// Thrown when a backend cannot start because values are missing.
class ConfigurationError extends Error {
  /// Which backend could not start.
  final String backend;

  /// Every requirement that was not satisfied.
  final List<Requirement> missing;

  /// Reports that [backend] is missing [missing].
  ConfigurationError({required this.backend, required this.missing});

  @override
  String toString() {
    final lines = missing
        .map((requirement) => '  ${requirement.name}: ${requirement.purpose}')
        .join('\n');
    return 'Cannot start the $backend backend, '
        '${missing.length} value(s) missing:\n$lines';
  }
}

/// What a backend needs before it can start.
///
/// Pylon reads no environment and no file. It cannot: `String.fromEnvironment`
/// only works on a literal at the site that calls it, so the values have to be
/// read by the project and handed over. What this adds is that they are declared
/// in one place instead of being pulled out of the air deep inside a client, and
/// that a missing one is reported properly.
///
/// ```dart
/// class RestConfig extends Config {
///   const RestConfig({required this.url, required this.appKey});
///
///   factory RestConfig.fromEnvironment() => const RestConfig(
///     url: String.fromEnvironment('ADMIN_URL'),
///     appKey: String.fromEnvironment('ADMIN_APP_KEY'),
///   );
///
///   final String url;
///   final String appKey;
///
///   @override
///   String get backend => 'rest';
///
///   @override
///   List<Requirement> get requirements => [
///     Requirement(name: 'ADMIN_URL', value: url, purpose: 'Where the API lives.'),
///     Requirement(name: 'ADMIN_APP_KEY', value: appKey, purpose: 'Identifies this app to the gateway.'),
///   ];
/// }
/// ```
abstract base class Config {
  /// Allows subclasses to be const.
  const Config();

  /// Which backend this configures, as it appears in an error message.
  String get backend;

  /// Every value the backend needs, satisfied or not.
  List<Requirement> get requirements;

  /// Every requirement that was not satisfied.
  List<Requirement> get missing =>
      requirements.where((requirement) => !requirement.isSatisfied).toList();

  /// Whether the backend has everything it needs.
  bool get isComplete => missing.isEmpty;

  /// Throws a [ConfigurationError] listing everything that is missing.
  ///
  /// All of them at once, and outside debug mode too. An assertion reports the
  /// first and only while assertions run, which means a build that is missing
  /// three values fails three times, and a release build not at all.
  void validate() {
    final absent = missing;
    if (absent.isEmpty) return;
    throw ConfigurationError(backend: backend, missing: absent);
  }
}
