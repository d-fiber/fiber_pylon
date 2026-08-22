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

/// The wall between a project and whatever is currently answering it.
///
/// Pylon exists so that unplugging a backend and plugging in another changes one
/// line of wiring and nothing else. It is built on one refusal: **pylon
/// understands neither side.** It does not know what a brand is, what a route
/// is, what a credential looks like, or what can go wrong. It knows how to let
/// something through, or not.
///
/// Everything here is therefore either a shape a project fills in, or a policy
/// that is identical whatever fills it in. Nothing infers, nothing recognises a
/// name, nothing assumes a format. Where a decision belongs to the project, it
/// is a required argument, never a default that happens to be right most of the
/// time.
///
/// ## The two halves
///
/// **The barrier**, which the contract sees: [Result] and its two variants,
/// [Fault], [FaultMapper], [Backend], [SdkHandle], [Config]. This is what a
/// service layer touches, and it does not change when the backend does.
///
/// **The toolkit**, which only adapters see: [RestClient] and what it needs,
/// [CredentialManager], [CallGuard], [SocketChannel], [ChannelKeeper],
/// [HealthMonitor], [Preference], [KeyValueStore], [Observable], [Reporter],
/// [Backoff]. Each is a mechanism every backend would otherwise rewrite, and
/// rewrite worse the second time.
///
/// `package:fiber_pylon/fiber_pylon_io.dart` carries the one piece that needs `dart:io`, a
/// [SocketLink] over a WebSocket. It is separate so that importing pylon does
/// not stop a project from compiling for the web.
///
/// ## The one thing pylon does assume
///
/// That both ends of the swap are REST. [RestClient] therefore speaks HTTP, and
/// [RestMethod] is a closed list, because these are a protocol's own words
/// rather than a guess about a project. What stays outside is every judgement
/// the protocol does not make: which statuses are failures, what an error body
/// looks like, how a call is authenticated. Those are asked for, through a
/// [RestClassifier] and a [RestHeaders].
///
/// ## Where the boundary actually is
///
/// It is [Fault], and what makes it work is that pylon never reads it. A fault
/// carries a signal from the adapter's own vocabulary, an enum the adapter
/// declares:
///
/// ```dart
/// enum RestSignal { unauthorized, forbidden, vpnRequired, nameEmpty, noRoute }
/// ```
///
/// A [FaultMapper] then turns that signal into the error one operation declares,
/// through a table the project wrote, with both sides typed and checked by the
/// compiler. Where pylon needs to act on a failure, it is handed a set of
/// signals rather than left to interpret one: [CredentialManager] is told which
/// signals mean the credential is dead, [CallGuard] which are worth renewing
/// for, and even the refusal [CallGuard] issues for a duplicate call is named by
/// the project.
///
/// That is the whole discipline. Any list of failure kinds pylon offered would
/// be a guess about the projects it has not met.
///
/// ## What is deliberately absent
///
/// No token format, no notion of a session, no list of error kinds, no envelope
/// around a response body, no rule about which status means what, no environment
/// reading, no code generation. Every one of those belongs to one server rather
/// than to REST, and a wall that took a side would stop being a wall.
library;

export 'src/backend/backend.dart';
export 'src/backend/config.dart';
export 'src/backend/handle.dart';
export 'src/call/guard.dart';
export 'src/channel/backoff.dart';
export 'src/channel/channel.dart';
export 'src/channel/keeper.dart';
export 'src/channel/socket.dart';
export 'src/credential/credential.dart';
export 'src/credential/manager.dart';
export 'src/credential/refresher.dart';
export 'src/credential/store.dart';
export 'src/fault/fault.dart';
export 'src/fault/mapper.dart';
export 'src/health/monitor.dart';
export 'src/reactive/observable.dart';
export 'src/report/reporter.dart';
export 'src/rest/classifier.dart';
export 'src/rest/client.dart';
export 'src/rest/request.dart';
export 'src/rest/response.dart';
export 'src/result/result.dart';
export 'src/storage/preference.dart';
export 'src/storage/store.dart';
