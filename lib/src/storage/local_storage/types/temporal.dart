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

/// Reads a value back the way [DatabaseType.timestamp], [DatabaseType.date] and [DatabaseType.time] wrote it.
extension TemporalDecoding on DatabaseType {
  /// This value as a UTC [DateTime], the same convention [timestamp] wrote
  /// it under: milliseconds since the Unix epoch.
  ///
  /// Throws a [StateError] if this is not a [Integer].
  DateTime get asDateTime {
    if (this case Integer(value: final milliseconds)) {
      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    }
    throw StateError('$this is not a timestamp.');
  }

  /// This value as a [Date], the same convention [date] wrote it
  /// under: its own midnight, UTC, in milliseconds since the Unix epoch.
  ///
  /// Throws a [StateError] if this is not a [Integer].
  Date get asDate {
    if (this case Integer(value: final milliseconds)) {
      return Date.fromDateTime(DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true));
    }
    throw StateError('$this is not a date.');
  }

  /// This value as a [Time], the same convention [time] wrote it
  /// under: its JSON form.
  ///
  /// Throws a [StateError] if this is not a [Varchar].
  Time get asTime => _asJson(Time.fromJson, 'time');
}

/// A calendar date, with no time of day — [year]-[month]-[day].
final class Date extends Equatable {
  /// The date [year]-[month]-[day].
  const Date({required this.year, required this.month, required this.day});

  /// The calendar year, astronomical numbering (`0` is 1 BC).
  final int year;

  /// The calendar month, `1` through `12`.
  final int month;

  /// The day of the month, `1` through however many days [month] has.
  final int day;

  /// [value]'s own date, discarding its time of day.
  factory Date.fromDateTime(DateTime value) => Date(year: value.year, month: value.month, day: value.day);

  /// This date, at midnight UTC.
  DateTime toDateTime() => DateTime.utc(year, month, day);

  /// Rebuilds the [Date] [toJson] wrote.
  factory Date.fromJson(Map<String, dynamic> json) =>
      Date(year: json['year'] as int, month: json['month'] as int, day: json['day'] as int);

  /// This date's own fields, in the shape [Date.fromJson] rebuilds
  /// from.
  Map<String, dynamic> toJson() => {'year': year, 'month': month, 'day': day};

  @override
  List<Object?> get props => [year, month, day];
}

/// A time of day, with no calendar date — [hour]:[minute]:[second], to
/// [millisecond] precision.
final class Time extends Equatable {
  /// The time [hour]:[minute]:[second].[millisecond].
  const Time({required this.hour, required this.minute, this.second = 0, this.millisecond = 0, this.utcOffset});

  /// The hour, `0` through `23`.
  final int hour;

  /// The minute, `0` through `59`.
  final int minute;

  /// The second, `0` through `59`.
  final int second;

  /// The millisecond, `0` through `999`.
  final int millisecond;

  /// This time's own offset from UTC, when it carries one at all —
  /// Postgres's own `TIME WITH TIME ZONE`. `null` for a bare time of day,
  /// which is what most columns actually want.
  final Duration? utcOffset;

  /// Rebuilds the [Time] [toJson] wrote.
  factory Time.fromJson(Map<String, dynamic> json) => Time(
    hour: json['hour'] as int,
    minute: json['minute'] as int,
    second: json['second'] as int,
    millisecond: json['millisecond'] as int,
    utcOffset: json['utcOffsetMinutes'] == null ? null : Duration(minutes: json['utcOffsetMinutes'] as int),
  );

  /// This time's own fields, in the shape [Time.fromJson] rebuilds
  /// from.
  Map<String, dynamic> toJson() => {
    'hour': hour,
    'minute': minute,
    'second': second,
    'millisecond': millisecond,
    'utcOffsetMinutes': utcOffset?.inMinutes,
  };

  @override
  List<Object?> get props => [hour, minute, second, millisecond, utcOffset];
}
