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

/// Reads a value back the way [DatabaseType.range] wrote it.
extension RangeDecoding on DatabaseType {
  /// This value as [NumberRangeBounds], the same convention [range] wrote a
  /// [RangeBounds.num] under: both bounds exactly as given.
  ///
  /// Throws a [StateError] if this is not a [Varchar].
  NumberRangeBounds get asNumberRange {
    final json = _decodeJson('number range');
    return NumberRangeBounds._(
      subtype: RangeSubtype.values.byName(json['subtype'] as String),
      lower: json['lower'] as num?,
      upper: json['upper'] as num?,
      lowerInclusive: json['lowerInclusive'] as bool,
      upperInclusive: json['upperInclusive'] as bool,
    );
  }

  /// This value as [DateTimeRangeBounds], the same convention [range] wrote
  /// a [RangeBounds.datetime] under: each bound, when present, in UTC.
  ///
  /// Throws a [StateError] if this is not a [Varchar].
  DateTimeRangeBounds get asDateTimeRange {
    final json = _decodeJson('date range');
    final lower = json['lower'] as int?;
    final upper = json['upper'] as int?;
    return DateTimeRangeBounds._(
      subtype: RangeSubtype.values.byName(json['subtype'] as String),
      lower: lower == null ? null : DateTime.fromMillisecondsSinceEpoch(lower, isUtc: true),
      upper: upper == null ? null : DateTime.fromMillisecondsSinceEpoch(upper, isUtc: true),
      lowerInclusive: json['lowerInclusive'] as bool,
      upperInclusive: json['upperInclusive'] as bool,
    );
  }
}

/// Which Postgres range type a [RangeBounds] mirrors.
///
/// Kept for interoperability and self-description — a project's own schema
/// can say which of the six it means — not because this package reads it
/// back: [DatabaseType.range] already picks the right encoding from the
/// kind of [RangeBounds] it is given, regardless of which member is named
/// here.
enum RangeSubtype {
  /// Postgres's `int4range`.
  integer,

  /// Postgres's `int8range`.
  bigint,

  /// Postgres's `numrange`.
  numeric,

  /// Postgres's `tsrange`.
  timestamp,

  /// Postgres's `tstzrange`.
  timestamptz,

  /// Postgres's `daterange`.
  date,
}

/// A Postgres-style range: bounded by a lower and an upper end, each either
/// inclusive or exclusive, and either end entirely absent for a range
/// unbounded on that side. Of exactly one of two kinds: numbers
/// ([RangeBounds.num]) or dates ([RangeBounds.datetime]), nothing else.
///
/// Sealed and built only through those two factories, so a `switch` over a
/// [RangeBounds] is exhaustive with [NumberRangeBounds] and
/// [DateTimeRangeBounds]. Postgres's own default shape, `[lower, upper)`, is
/// the default here too: [lowerInclusive] defaults to `true`,
/// [upperInclusive] to `false`. Nothing here checks that the [subtype] a
/// project names matches the kind of bounds it gave.
sealed class RangeBounds extends Equatable {
  const RangeBounds._({required this.subtype, required this.lowerInclusive, required this.upperInclusive});

  /// The range from [lower] to [upper], both numbers.
  const factory RangeBounds.num({
    required RangeSubtype subtype,
    num? lower,
    num? upper,
    bool lowerInclusive,
    bool upperInclusive,
  }) = NumberRangeBounds._;

  /// The range from [lower] to [upper], both dates.
  const factory RangeBounds.datetime({
    required RangeSubtype subtype,
    DateTime? lower,
    DateTime? upper,
    bool lowerInclusive,
    bool upperInclusive,
  }) = DateTimeRangeBounds._;

  /// Which Postgres range type this mirrors.
  final RangeSubtype subtype;

  /// This range's own lower bound. Unbounded below when `null`.
  Object? get lower;

  /// This range's own upper bound. Unbounded above when `null`.
  Object? get upper;

  /// Whether [lower] itself is part of this range. Meaningless when [lower]
  /// is `null`.
  final bool lowerInclusive;

  /// Whether [upper] itself is part of this range. Meaningless when [upper]
  /// is `null`.
  final bool upperInclusive;

  @override
  List<Object?> get props => [subtype, lower, upper, lowerInclusive, upperInclusive];
}

/// A [RangeBounds] between two numbers.
final class NumberRangeBounds extends RangeBounds {
  const NumberRangeBounds._({
    required super.subtype,
    this.lower,
    this.upper,
    super.lowerInclusive = true,
    super.upperInclusive = false,
  }) : super._();

  @override
  final num? lower;

  @override
  final num? upper;
}

/// A [RangeBounds] between two dates.
final class DateTimeRangeBounds extends RangeBounds {
  const DateTimeRangeBounds._({
    required super.subtype,
    this.lower,
    this.upper,
    super.lowerInclusive = true,
    super.upperInclusive = false,
  }) : super._();

  @override
  final DateTime? lower;

  @override
  final DateTime? upper;
}
