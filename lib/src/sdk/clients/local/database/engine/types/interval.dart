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

/// Reads back a value written by [Value.interval].
extension IntervalDecoding on Value {
  /// This value as [NumberBounds].
  ///
  /// Use it on a value written from an [IntervalBounds.num]. A bound that was a
  /// whole-number [double] comes back as an [int] of the same value.
  ///
  /// Throws a [StateError] if this is not a [Varchar]. Throws a [FormatException] or a
  /// [TypeError] if its text is not what was written.
  NumberBounds get asNumberBounds {
    final json = _decodeJson('number interval');
    return NumberBounds._(start: json['start'] as num, end: json['end'] as num);
  }

  /// This value as [DateTimeBounds], each bound in UTC.
  ///
  /// Use it on a value written from an [IntervalBounds.datetime].
  ///
  /// Throws a [StateError] if this is not a [Varchar]. Throws a [FormatException] or a
  /// [TypeError] if its text is not what was written.
  DateTimeBounds get asDateTimeBounds {
    final json = _decodeJson('date interval');
    return DateTimeBounds._(
      start: DateTime.fromMillisecondsSinceEpoch(json['start'] as int, isUtc: true),
      end: DateTime.fromMillisecondsSinceEpoch(json['end'] as int, isUtc: true),
    );
  }
}

/// The two ends of an interval, either two numbers or two dates.
///
/// Build one with [IntervalBounds.num] or [IntervalBounds.datetime], then
/// `switch` over [NumberBounds] and [DateTimeBounds] to read the ends with
/// their own type. Nothing requires the first end to be the lesser one, and
/// nothing reorders them: the two values read back in the order they were given.
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

  /// The first end of this interval.
  final num start;

  /// The second end of this interval.
  final num end;

  @override
  List<Object?> get props => [start, end];
}

/// An [IntervalBounds] between two dates.
final class DateTimeBounds extends IntervalBounds {
  const DateTimeBounds._({required this.start, required this.end}) : super._();

  /// The first end of this interval.
  final DateTime start;

  /// The second end of this interval.
  final DateTime end;

  @override
  List<Object?> get props => [start, end];
}
