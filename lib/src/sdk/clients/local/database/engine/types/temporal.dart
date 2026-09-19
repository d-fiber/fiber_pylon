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

/// Reads a value back the way [Value.timestamp], [Value.date] and [Value.time] wrote it.
extension TemporalDecoding on Value {
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

  /// This value as a [Time], the same convention [time] wrote it under:
  /// text such as `09:30:15.500`, or `09:30:15.500+01:00` with an offset.
  ///
  /// Throws a [StateError] if this is not a [Varchar]. Throws a
  /// [FormatException] if its text is not of that shape.
  Time get asTime {
    if (this case Varchar(value: final stored)) return _timeFromText(stored);
    throw StateError('$this is not a time.');
  }
}

final RegExp _timeText = RegExp(r'^(\d{2}):(\d{2}):(\d{2})\.(\d{3})(?:([+-])(\d{2}):(\d{2}))?$');

String _twoDigits(int value) => value.toString().padLeft(2, '0');

const int _largestOffsetMinutes = 23 * 60 + 59;

String _timeToText(Time time) {
  final offset = time.utcOffset;
  if (offset != null &&
      (offset.inMicroseconds % Duration.microsecondsPerMinute != 0 || offset.inMinutes.abs() > _largestOffsetMinutes)) {
    throw ArgumentError.value(offset, 'utcOffset', 'Must be a whole number of minutes, less than a day away from UTC.');
  }
  final suffix = offset == null
      ? ''
      : '${offset.isNegative ? '-' : '+'}${_twoDigits(offset.inHours.abs())}:${_twoDigits(offset.inMinutes.abs() % 60)}';
  final millisecond = time.millisecond.toString().padLeft(3, '0');
  return '${_twoDigits(time.hour)}:${_twoDigits(time.minute)}:${_twoDigits(time.second)}.$millisecond$suffix';
}

Time _timeFromText(String text) {
  final match = _timeText.firstMatch(text);
  if (match == null) throw FormatException('Not a time of day, expected HH:MM:SS.mmm with an optional offset.', text);
  final sign = match.group(5);
  final offsetMinutes = sign == null ? null : int.parse(match.group(6)!) * 60 + int.parse(match.group(7)!);
  return Time(
    hour: int.parse(match.group(1)!),
    minute: int.parse(match.group(2)!),
    second: int.parse(match.group(3)!),
    millisecond: int.parse(match.group(4)!),
    utcOffset: offsetMinutes == null ? null : Duration(minutes: sign == '-' ? -offsetMinutes : offsetMinutes),
  );
}

/// A calendar date, with no time of day — [year]-[month]-[day].
final class Date extends Equatable implements Comparable<Date> {
  /// The date [year]-[month]-[day].
  ///
  /// Asserts that [month] is `1` through `12` and that [day] exists in that
  /// month of that year, leap years included. Without it, [toDateTime] would
  /// roll 31 February over into March instead of refusing it.
  const Date({required this.year, required this.month, required this.day})
    : assert(month >= 1 && month <= 12, 'month must be 1 through 12.'),
      assert(
        day >= 1 &&
            day <=
                (month == 2
                    ? ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28)
                    : (month == 4 || month == 6 || month == 9 || month == 11)
                    ? 30
                    : 31),
        'day must exist in the given month of the given year.',
      );

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

  /// Orders dates by the calendar, the same order SQLite sorts their stored
  /// milliseconds in.
  @override
  int compareTo(Date other) => toDateTime().compareTo(other.toDateTime());

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
final class Time extends Equatable implements Comparable<Time> {
  /// The time [hour]:[minute]:[second].[millisecond].
  ///
  /// Asserts that every field sits inside the range its own documentation
  /// gives.
  const Time({required this.hour, required this.minute, this.second = 0, this.millisecond = 0, this.utcOffset})
    : assert(hour >= 0 && hour <= 23, 'hour must be 0 through 23.'),
      assert(minute >= 0 && minute <= 59, 'minute must be 0 through 59.'),
      assert(second >= 0 && second <= 59, 'second must be 0 through 59.'),
      assert(millisecond >= 0 && millisecond <= 999, 'millisecond must be 0 through 999.');

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

  /// Orders times by their stored text, the same order SQLite sorts them in,
  /// which is the order of the clock between two times with the same offset.
  @override
  int compareTo(Time other) => _timeToText(this).compareTo(_timeToText(other));

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
