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

/// Reads a value back the way [Value.range] wrote it.
///
/// Use the accessor of the kind the range was written as. Reading it as another
/// kind throws, or gives bounds that mean nothing.
extension RangeDecoding on Value {
  /// This value as a [RangeBounds.num] range.
  ///
  /// A bound that was a whole-number [double] reads back as an [int].
  ///
  /// Throws a [StateError] if this is not a [Varchar]. Throws a [FormatException] or a
  /// [TypeError] if its text is not what was written.
  NumberRangeBounds get asNumberRange {
    final json = _decodeJson('number range');
    return NumberRangeBounds._(
      subtype: NumberRangeSubtype.values.byName(json['subtype'] as String),
      lower: json['lower'] as num?,
      upper: json['upper'] as num?,
      lowerInclusive: json['lowerInclusive'] as bool,
      upperInclusive: json['upperInclusive'] as bool,
    );
  }

  /// This value as a [RangeBounds.datetime] range, each bound in UTC.
  ///
  /// Throws a [StateError] if this is not a [Varchar]. Throws a [FormatException] or a
  /// [TypeError] if its text is not what was written.
  DateTimeRangeBounds get asDateTimeRange {
    final json = _decodeJson('date time range');
    final lower = json['lower'] as int?;
    final upper = json['upper'] as int?;
    return DateTimeRangeBounds._(
      subtype: DateTimeRangeSubtype.values.byName(json['subtype'] as String),
      lower: lower == null ? null : DateTime.fromMillisecondsSinceEpoch(lower, isUtc: true),
      upper: upper == null ? null : DateTime.fromMillisecondsSinceEpoch(upper, isUtc: true),
      lowerInclusive: json['lowerInclusive'] as bool,
      upperInclusive: json['upperInclusive'] as bool,
    );
  }

  /// This value as a [RangeBounds.date] range.
  ///
  /// Throws a [StateError] if this is not a [Varchar]. Throws a [FormatException] or a
  /// [TypeError] if its text is not what was written.
  DateRangeBounds get asDateRange {
    final json = _decodeJson('date range');
    final lower = json['lower'] as int?;
    final upper = json['upper'] as int?;
    return DateRangeBounds._(
      lower: lower == null ? null : Date.fromDateTime(DateTime.fromMillisecondsSinceEpoch(lower, isUtc: true)),
      upper: upper == null ? null : Date.fromDateTime(DateTime.fromMillisecondsSinceEpoch(upper, isUtc: true)),
      lowerInclusive: json['lowerInclusive'] as bool,
      upperInclusive: json['upperInclusive'] as bool,
    );
  }
}

/// Which Postgres range type over numbers a [RangeBounds.num] mirrors.
///
/// A label only: it is saved and read back with the range, and does not change
/// how the bounds are stored.
enum NumberRangeSubtype {
  /// Postgres's `int4range`.
  integer,

  /// Postgres's `int8range`.
  bigint,

  /// Postgres's `numrange`.
  numeric,
}

/// Which Postgres range type over instants a [RangeBounds.datetime] mirrors.
///
/// A label only, like [NumberRangeSubtype]: both values store the bounds the
/// same way, in UTC.
enum DateTimeRangeSubtype {
  /// Postgres's `tsrange`.
  timestamp,

  /// Postgres's `tstzrange`.
  timestamptz,
}

/// A Postgres-style range over numbers, instants or calendar dates.
///
/// Each end is inclusive or exclusive, and a `null` end leaves the range
/// unbounded on that side. Without arguments a range is `[lower, upper)`, as in
/// Postgres: [lowerInclusive] is `true` and [upperInclusive] is `false`.
///
/// Built through [RangeBounds.num], [RangeBounds.datetime] or [RangeBounds.date].
/// A `switch` over a [RangeBounds] is exhaustive with [NumberRangeBounds],
/// [DateTimeRangeBounds] and [DateRangeBounds], which carry the bounds.
sealed class RangeBounds extends Equatable {
  const RangeBounds._({required this.lowerInclusive, required this.upperInclusive});

  /// The range from [lower] to [upper], both numbers.
  const factory RangeBounds.num({
    required NumberRangeSubtype subtype,
    num? lower,
    num? upper,
    bool lowerInclusive,
    bool upperInclusive,
  }) = NumberRangeBounds._;

  /// The range from [lower] to [upper], both instants.
  const factory RangeBounds.datetime({
    required DateTimeRangeSubtype subtype,
    DateTime? lower,
    DateTime? upper,
    bool lowerInclusive,
    bool upperInclusive,
  }) = DateTimeRangeBounds._;

  /// The range from [lower] to [upper], both calendar dates, like the Postgres
  /// `daterange`.
  const factory RangeBounds.date({Date? lower, Date? upper, bool lowerInclusive, bool upperInclusive}) =
      DateRangeBounds._;

  /// Whether the lower bound itself is part of this range.
  ///
  /// Ignored when this range is unbounded below, though it still counts in
  /// equality.
  final bool lowerInclusive;

  /// Whether the upper bound itself is part of this range.
  ///
  /// Ignored when this range is unbounded above, though it still counts in
  /// equality.
  final bool upperInclusive;
}

/// A [RangeBounds] between two numbers.
final class NumberRangeBounds extends RangeBounds {
  const NumberRangeBounds._({
    required this.subtype,
    this.lower,
    this.upper,
    super.lowerInclusive = true,
    super.upperInclusive = false,
  }) : super._();

  /// The Postgres range type over numbers this range mirrors.
  final NumberRangeSubtype subtype;

  /// The lower end of this range, or `null` when it is unbounded below.
  final num? lower;

  /// The upper end of this range, or `null` when it is unbounded above.
  final num? upper;

  @override
  List<Object?> get props => [subtype, lower, upper, lowerInclusive, upperInclusive];
}

/// A [RangeBounds] between two instants.
final class DateTimeRangeBounds extends RangeBounds {
  const DateTimeRangeBounds._({
    required this.subtype,
    this.lower,
    this.upper,
    super.lowerInclusive = true,
    super.upperInclusive = false,
  }) : super._();

  /// The Postgres range type over instants this range mirrors.
  final DateTimeRangeSubtype subtype;

  /// The lower end of this range, or `null` when it is unbounded below.
  final DateTime? lower;

  /// The upper end of this range, or `null` when it is unbounded above.
  final DateTime? upper;

  @override
  List<Object?> get props => [subtype, lower, upper, lowerInclusive, upperInclusive];
}

/// A [RangeBounds] between two calendar dates.
final class DateRangeBounds extends RangeBounds {
  const DateRangeBounds._({this.lower, this.upper, super.lowerInclusive = true, super.upperInclusive = false})
    : super._();

  /// The lower end of this range, or `null` when it is unbounded below.
  final Date? lower;

  /// The upper end of this range, or `null` when it is unbounded above.
  final Date? upper;

  @override
  List<Object?> get props => [lower, upper, lowerInclusive, upperInclusive];
}
