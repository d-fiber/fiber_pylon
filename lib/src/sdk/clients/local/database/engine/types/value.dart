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

/// One value SQLite can store: an [Integer], a [Real], a [Varchar], a [Blob] or
/// a [Nil].
///
/// Sealed, so that a value sqflite would reject or silently mangle cannot be
/// handed to it.
///
/// Anything else a project stores is written into one of those five by a static
/// method of this class: [boolean], [timestamp], [date], [time], [uuid],
/// [randomUuid], [enum_], [list], [interval], [range], and [point], [line],
/// [segment], [box], [path], [polygon] and [circle] for shapes on a map. Read it
/// back with the matching getter on [Value], such as `asBoolean`, `asDateTime`
/// or `asPoint`.
sealed class Value extends Equatable {
  const Value();

  /// A signed integer, up to 64 bits.
  const factory Value.integer(int value) = Integer;

  /// A floating point value.
  ///
  /// A NaN cannot be stored, see [Real].
  const factory Value.real(double value) = Real;

  /// UTF-8 text.
  ///
  /// Named after `VARCHAR` rather than `TEXT`, so that it is not mistaken for
  /// [ColumnType.text], which is the type a column declares.
  const factory Value.varchar(String value) = Varchar;

  /// Raw bytes, stored exactly as given.
  const factory Value.blob(Uint8List value) = Blob;

  /// The absence of a value.
  const factory Value.nil() = Nil;

  /// [value] encoded by [encode], or [nil] when [value] is `null`.
  ///
  /// The write side of a nullable column, so that a nullable field needs no
  /// conditional at each call site: `Value.nullable(note, Value.varchar)`. Read
  /// the column back with [RowReading.nullable].
  static Value nullable<T extends Object>(T? value, Value Function(T value) encode) =>
      value == null ? const Nil() : encode(value);

  /// [value] as an [Integer] of `1` or `0`, since SQLite has no boolean.
  ///
  /// Read one back with `asBoolean`.
  static Integer boolean(bool value) => Integer(value ? 1 : 0);

  /// [milliseconds] since the Unix epoch, as an [Integer].
  ///
  /// Takes the millisecond count rather than a [DateTime] so that no time zone
  /// is ever guessed: the epoch is UTC, so devices in different time zones agree
  /// on what a stored value means. Pass [DateTime.millisecondsSinceEpoch] to
  /// store a [DateTime]. Read one back with `asDateTime`, which returns a
  /// [DateTime] in UTC.
  static Integer timestamp(int milliseconds) => Integer(milliseconds);

  /// [value] as an [Integer] holding its midnight UTC, in milliseconds since the
  /// Unix epoch.
  ///
  /// A [Date] has no time of day, so the same date reads back on every device in
  /// every time zone. Read one back with `asDate`.
  static Integer date(Date value) => Integer(value.toDateTime().millisecondsSinceEpoch);

  /// [value] as a [Varchar] holding its text form, `09:30:15.500`, or
  /// `09:30:15.500+01:00` when [Time.utcOffset] is set.
  ///
  /// An ordering filter on a column of these compares the times of day. Two
  /// times with different offsets compare by what their clocks read, not by the
  /// instant they name. Read one back with `asTime`.
  ///
  /// Throws an [ArgumentError] if [Time.utcOffset] is not a whole number of
  /// minutes, or is a day or more away from UTC in either direction, since the
  /// stored text could not read it back.
  static Varchar time(Time value) => Varchar(_timeToText(value));

  /// [value] as a [Varchar] holding its name.
  ///
  /// Stored by name rather than by index, so reordering an enum never changes
  /// what an existing row reads back as. Read one back with `asEnum`, given the
  /// `values` of the same enum.
  ///
  /// An ordering filter on a column of these compares the names alphabetically,
  /// not in declaration order.
  static Varchar enum_(Enum value) => Varchar(value.name);

  /// [value] as a [Varchar] holding its JSON form.
  ///
  /// Meant for a list whose elements are already JSON values: an [int], a
  /// [double], a [String], a [bool], a `Map<String, dynamic>` or `null`. For a
  /// list of a project's own type, use [ListJson].
  static Varchar list<T>(List<T> value) => Varchar(jsonEncode(value));

  /// [value] as a [Varchar] holding its text form.
  ///
  /// The text is lower-case unless [value] was built with [UuidValue.raw].
  /// Read one back with `asUuid`, which validates the text.
  static Varchar uuid(UuidValue value) => Varchar(value.uuid);

  /// A new random UUID (version 4), as a [Varchar].
  ///
  /// The identifier comes from a cryptographically strong random source, so two
  /// inserts in the same millisecond practically never collide. Call `asUuid` on
  /// the result to keep the identifier it holds.
  static Varchar randomUuid() => Varchar(_uuidGenerator.v4());

  /// [value] as a [Varchar] holding its JSON form, `{"lat": ..., "lng": ...}`.
  ///
  /// Read one back with `asPoint`.
  static Varchar point(Location value) => Varchar(jsonEncode(value.toJson()));

  /// [value] as a [Varchar] holding its JSON form.
  static Varchar line(LocationLine value) => Varchar(jsonEncode(value.toJson()));

  /// [value] as a [Varchar] holding its JSON form.
  static Varchar segment(LocationSegment value) => Varchar(jsonEncode(value.toJson()));

  /// [value] as a [Varchar] holding its JSON form.
  static Varchar box(LocationBox value) => Varchar(jsonEncode(value.toJson()));

  /// [value] as a [Varchar] holding its JSON form.
  static Varchar path(LocationPath value) => Varchar(jsonEncode(value.toJson()));

  /// [value] as a [Varchar] holding its JSON form.
  static Varchar polygon(LocationPolygon value) => Varchar(jsonEncode(value.toJson()));

  /// [value] as a [Varchar] holding its JSON form.
  static Varchar circle(LocationCircle value) => Varchar(jsonEncode(value.toJson()));

  /// [value] as a [Varchar] holding its two bounds.
  ///
  /// A bound of an [IntervalBounds.num] that is a whole-number [double] reads
  /// back as an [int]. The bounds of an [IntervalBounds.datetime] read back in
  /// UTC. Read one back with `asNumberBounds` or `asDateTimeBounds`, whichever
  /// kind it was written as.
  static Varchar interval(IntervalBounds value) => switch (value) {
    NumberBounds(:final start, :final end) => Varchar(
      jsonEncode({'start': _canonicalNumber(start), 'end': _canonicalNumber(end)}),
    ),
    DateTimeBounds(:final start, :final end) => Varchar(
      jsonEncode({'start': start.toUtc().millisecondsSinceEpoch, 'end': end.toUtc().millisecondsSinceEpoch}),
    ),
  };

  /// [value] as a [Varchar] holding its bounds, their inclusivity and its
  /// subtype.
  ///
  /// A bound of a [RangeBounds.num] that is a whole-number [double] reads back
  /// as an [int]. The bounds of a [RangeBounds.datetime] read back in UTC.
  /// [DateTimeRangeSubtype.timestamp] and [DateTimeRangeSubtype.timestamptz] are
  /// stored alike, apart from their name.
  ///
  /// Read one back with `asNumberRange`, `asDateTimeRange` or `asDateRange`,
  /// whichever kind it was written as.
  static Varchar range(RangeBounds value) => switch (value) {
    NumberRangeBounds(:final subtype, :final lower, :final upper) => Varchar(
      jsonEncode({
        'subtype': subtype.name,
        'lower': _canonicalNumber(lower),
        'upper': _canonicalNumber(upper),
        'lowerInclusive': value.lowerInclusive,
        'upperInclusive': value.upperInclusive,
      }),
    ),
    DateTimeRangeBounds(:final subtype, :final lower, :final upper) => Varchar(
      jsonEncode({
        'subtype': subtype.name,
        'lower': lower?.toUtc().millisecondsSinceEpoch,
        'upper': upper?.toUtc().millisecondsSinceEpoch,
        'lowerInclusive': value.lowerInclusive,
        'upperInclusive': value.upperInclusive,
      }),
    ),
    DateRangeBounds(:final lower, :final upper) => Varchar(
      jsonEncode({
        'subtype': 'date',
        'lower': lower?.toDateTime().millisecondsSinceEpoch,
        'upper': upper?.toDateTime().millisecondsSinceEpoch,
        'lowerInclusive': value.lowerInclusive,
        'upperInclusive': value.upperInclusive,
      }),
    ),
  };

  /// This value in the shape sqflite accepts and hands back.
  Object? _toNative();

  Map<String, dynamic> _decodeJson(String shape) {
    if (this case Varchar(value: final stored)) return jsonDecode(stored) as Map<String, dynamic>;
    throw StateError('$this is not a $shape.');
  }

  T _asJson<T>(T Function(Map<String, dynamic> json) fromJson, String shape) => fromJson(_decodeJson(shape));
}

final Uuid _uuidGenerator = const Uuid();

/// The largest integer a [double] holds without rounding, `2^53`.
const int _largestExactInteger = 9007199254740992;

/// [number] as an [int] when it is a whole number a [double] holds exactly, so
/// that `3` and `3.0` are written as the same text and an equality filter
/// treats them as the one value they are, and [number] unchanged otherwise.
num? _canonicalNumber(num? number) =>
    number != null &&
        number is! int &&
        number.isFinite &&
        number == number.truncate() &&
        number.abs() < _largestExactInteger
    ? number.toInt()
    : number;

/// The absence of a value, SQL `NULL`.
final class Nil extends Value {
  /// The absence of a value. Prefer [Value.nil] over calling this directly.
  const Nil();

  @override
  Object? _toNative() => null;

  @override
  List<Object?> get props => const [];

  @override
  String toString() => 'Value.nil()';
}

/// A signed integer, up to 64 bits.
final class Integer extends Value {
  /// Wraps [value]. Prefer [Value.integer] over calling this directly, except
  /// where a signature asks for an [Integer] itself, such as
  /// [IntegerColumnBuilder.default_].
  const Integer(this.value);

  /// The integer this value wraps.
  final int value;

  @override
  Object? _toNative() => value;

  @override
  List<Object?> get props => [value];

  @override
  String toString() => 'Value.integer($value)';
}

/// A floating point value.
///
/// A NaN cannot be stored, since SQLite writes it as `NULL`: writing a row that
/// holds one throws an [ArgumentError].
final class Real extends Value {
  /// Wraps [value]. Prefer [Value.real] over calling this directly, except
  /// where a signature asks for a [Real] itself, such as
  /// [RealColumnBuilder.default_].
  const Real(this.value);

  /// The floating point value this value wraps.
  final double value;

  @override
  Object? _toNative() => value.isNaN
      ? throw ArgumentError.value(value, 'value', 'SQLite stores a NaN as NULL, so it could not be read back.')
      : value;

  @override
  List<Object?> get props => [value];

  @override
  String toString() => 'Value.real($value)';
}

/// UTF-8 text.
final class Varchar extends Value {
  /// Wraps [value]. Prefer [Value.varchar] over calling this directly, except
  /// where a signature asks for a [Varchar] itself, such as
  /// [TextColumnBuilder.default_].
  const Varchar(this.value);

  /// The text this value wraps.
  final String value;

  @override
  Object? _toNative() => value;

  @override
  List<Object?> get props => [value];

  @override
  String toString() => 'Value.varchar($value)';
}

/// Raw bytes, stored exactly as given.
final class Blob extends Value {
  /// Wraps [value]. Prefer [Value.blob] over calling this directly, except
  /// where a signature asks for a [Blob] itself, such as
  /// [BlobColumnBuilder.default_].
  const Blob(this.value);

  /// The bytes this value wraps.
  final Uint8List value;

  @override
  Object? _toNative() => value;

  @override
  List<Object?> get props => [value];

  @override
  String toString() => 'Value.blob(${value.length} byte(s))';
}

/// A row as [LocalDatabase] reads and writes it, from column name to [Value].
///
/// What a column holds is up to the schema of the project. Read a column with
/// [RowReading.required] or [RowReading.nullable] rather than by indexing the
/// map, which answers `null` for a missing column without naming it.
typedef RawRow = Map<String, Value>;

/// The [Value] for whatever sqflite handed back for one column.
///
/// Throws an [ArgumentError] if [native] is not one of the types sqflite hands
/// back, which should never happen for a value this library wrote through
/// [Value._toNative].
Value _fromNative(Object? native) => switch (native) {
  null => const Nil(),
  final int value => Integer(value),
  final double value => Real(value),
  final String value => Varchar(value),
  final Uint8List value => Blob(value),
  _ => throw ArgumentError.value(native, 'native', 'not a SQLite storage class'),
};

Map<String, Object?> _toNativeRow(RawRow row) =>
    row.map((column, value) => MapEntry(_quotedIdentifier(column), value._toNative()));

RawRow _fromNativeRow(Map<String, Object?> row) => row.map((column, value) => MapEntry(column, _fromNative(value)));

List<Object?>? _toNativeArgs(List<Value>? arguments) => arguments?.map((value) => value._toNative()).toList();
