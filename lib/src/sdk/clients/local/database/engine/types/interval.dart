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

part of '../database.dart';

/// Reads a value back the way [Value.interval] wrote it.
extension IntervalDecoding on Value {
  /// This value as [NumberBounds], the same convention [interval] wrote a
  /// [IntervalBounds.num] under: both bounds exactly as given.
  ///
  /// Throws a [StateError] if this is not a [Varchar].
  NumberBounds get asNumberBounds {
    final json = _decodeJson('number interval');
    return NumberBounds._(start: json['start'] as num, end: json['end'] as num);
  }

  /// This value as [DateTimeBounds], the same convention [interval] wrote a
  /// [IntervalBounds.datetime] under: each bound in UTC.
  ///
  /// Throws a [StateError] if this is not a [Varchar].
  DateTimeBounds get asDateTimeBounds {
    final json = _decodeJson('date interval');
    return DateTimeBounds._(
      start: DateTime.fromMillisecondsSinceEpoch(json['start'] as int, isUtc: true),
      end: DateTime.fromMillisecondsSinceEpoch(json['end'] as int, isUtc: true),
    );
  }
}

/// The two ends of an interval, of exactly one of two kinds: two numbers
/// ([IntervalBounds.num]) or two dates ([IntervalBounds.datetime]), nothing
/// else.
///
/// Sealed and built only through those two factories, so a `switch` over an
/// [IntervalBounds] is exhaustive with [NumberBounds] and [DateTimeBounds]
/// and nothing here can be handed a third kind. The ends live on those two
/// subclasses, each with its own type, so reading one never yields an
/// `Object` to cast. Neither end is required to be numerically or
/// chronologically the lesser of the two: a project that always normalises
/// its own bounds gets a predictable interval back, one that never does gets
/// exactly the two values it gave.
sealed class IntervalBounds extends Equatable {
  const IntervalBounds._();

  /// The interval from [start] to [end], both numbers.
  const factory IntervalBounds.num({required num start, required num end}) = NumberBounds._;

  /// The interval from [start] to [end], both dates.
  const factory IntervalBounds.datetime({required DateTime start, required DateTime end}) = DateTimeBounds._;
}

/// An [IntervalBounds] between two numbers.
final class NumberBounds extends IntervalBounds {
  const NumberBounds._({required this.start, required this.end}) : super._();

  /// One end of this interval.
  final num start;

  /// The other end of this interval.
  final num end;

  @override
  List<Object?> get props => [start, end];
}

/// An [IntervalBounds] between two dates.
final class DateTimeBounds extends IntervalBounds {
  const DateTimeBounds._({required this.start, required this.end}) : super._();

  /// One end of this interval.
  final DateTime start;

  /// The other end of this interval.
  final DateTime end;

  @override
  List<Object?> get props => [start, end];
}
