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

/// One environment variable a backend cannot start without.
class EnvironmentVariable extends Equatable {
  /// The name it is declared under, exactly as `String.fromEnvironment` was
  /// given it, so the message names something that can actually be searched
  /// for.
  final String name;

  /// What `String.fromEnvironment` read, `null` or empty when nothing was set.
  final String? value;

  /// Why the backend needs it, in one short sentence.
  ///
  /// This is what someone reads when they hit the error, usually without having
  /// ever seen the backend's source.
  final String reason;

  /// Declares that [name] is needed, for [reason], and was read as [value].
  const EnvironmentVariable({
    required this.name,
    required this.value,
    required this.reason,
  });

  /// Whether it was set to something usable.
  bool get isSatisfied => value != null && value?.isNotEmpty == true;

  @override
  List<Object?> get props => [name, value, reason];
}

/// Thrown when a backend cannot start because environment variables are
/// missing.
class ConfigurationError extends Error {
  /// Which backend could not start.
  final String backend;

  /// Every environment variable that was not satisfied.
  final List<EnvironmentVariable> missing;

  /// Reports that [backend] is missing [missing].
  ConfigurationError({required this.backend, required this.missing});

  @override
  String toString() {
    final lines = missing
        .map(
          (environmentVariable) =>
              '  ${environmentVariable.name}: ${environmentVariable.reason}',
        )
        .join('\n');
    return 'Cannot start the $backend backend, '
        '${missing.length} environment variable(s) missing:\n$lines';
  }
}

/// What a backend needs before it can start.
///
/// Pylon reads no environment and no file. It cannot: `String.fromEnvironment`
/// only works on a literal at the site that calls it, so the variables have to
/// be read by the project and handed over. What this adds is that they are
/// declared in one place instead of being pulled out of the air deep inside a
/// client, and that a missing one is reported properly.
///
/// ```dart
/// class RestConfiguration extends Configuration {
///   const RestConfiguration({required this.url, required this.appKey});
///
///   factory RestConfiguration.fromEnvironment() => const RestConfiguration(
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
///   List<EnvironmentVariable> get variables => [
///     EnvironmentVariable(
///       name: 'ADMIN_URL',
///       value: url,
///       reason: 'Where the API lives.',
///     ),
///     EnvironmentVariable(
///       name: 'ADMIN_APP_KEY',
///       value: appKey,
///       reason: 'Identifies this app to the gateway.',
///     ),
///   ];
/// }
/// ```
abstract base class Configuration {
  /// Allows subclasses to be const.
  const Configuration();

  /// Which backend this configures, as it appears in an error message.
  String get backend;

  /// Every environment variable the backend needs, satisfied or not.
  List<EnvironmentVariable> get variables;

  /// Every environment variable that was not satisfied.
  List<EnvironmentVariable> get missing => variables
      .where((environmentVariable) => !environmentVariable.isSatisfied)
      .toList();

  /// Whether the backend has everything it needs.
  bool get isComplete => missing.isEmpty;

  /// Throws a [ConfigurationError] listing everything that is missing.
  ///
  /// All of them at once, and outside debug mode too. An assertion reports the
  /// first and only while assertions run, which means a build that is missing
  /// three variables fails three times, and a release build not at all.
  void validate() {
    final absent = missing;
    if (absent.isEmpty) return;
    throw ConfigurationError(backend: backend, missing: absent);
  }
}
