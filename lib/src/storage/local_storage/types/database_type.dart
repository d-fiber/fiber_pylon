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

/// One value SQLite can actually store.
///
/// SQLite's own type system names exactly five storage classes — this closes
/// over them rather than accepting `Object?` and finding out only when
/// sqflite rejects, or silently mangles, something it was never meant to
/// hold. Everything else a project actually wants to store — a [bool], a
/// timestamp, a UUID, a shape on a map, a span between two values, a
/// Postgres-style range, a bare date or time of day, a named enum member,
/// a whole list — is a convention layered on top of one of these five,
/// never a sixth kind of its own: [boolean], [timestamp], [uuid], [point],
/// [line], [segment], [box], [path], [polygon], [circle], [interval],
/// [range], [date], [time], [enum_] and
/// [list] below are exactly that, named conventions rather than new
/// storage classes.
///
/// Each of those is written here, as a static method, because Dart offers
/// no way to add a static member to a class from another file. Reading one
/// back is the mirror image and has no such limit: `asBoolean`,
/// `asDateTime`, `asPoint` and the rest live beside the model each one
/// returns, as an extension on this class.
sealed class DatabaseType extends Equatable {
  const DatabaseType();

  /// A signed integer, up to 64 bits.
  const factory DatabaseType.integer(int value) = Integer;

  /// A floating point value.
  const factory DatabaseType.real(double value) = Real;

  /// UTF-8 text. Named after `VARCHAR` rather than `TEXT`, the keyword
  /// [ColumnType.text] itself renders, so the value a project writes and
  /// the type a column declares read as two different words rather than
  /// the same one used for two different things.
  const factory DatabaseType.varchar(String value) = Varchar;

  /// Raw bytes, stored exactly as given.
  const factory DatabaseType.blob(Uint8List value) = Blob;

  /// The absence of a value.
  const factory DatabaseType.nil() = Nil;

  /// [value] as an [Integer] of `1` or `0` — the convention every SQLite
  /// driver uses for a [bool], this one included, since SQLite has no
  /// boolean storage class of its own.
  static DatabaseType boolean(bool value) => Integer(value ? 1 : 0);

  /// [milliseconds] since the Unix epoch, stored as an [Integer] exactly as
  /// given.
  ///
  /// Takes the millisecond count itself rather than a [DateTime], so nothing
  /// here converts or guesses a time zone: the epoch is UTC by definition,
  /// and two devices in two time zones can never disagree on what a stored
  /// value means. Pass [DateTime.millisecondsSinceEpoch] to store a
  /// [DateTime]. Read one back with `asDateTime`, which hands back a UTC
  /// [DateTime]; call [DateTime.toLocal] on it if a caller needs local time.
  static DatabaseType timestamp(int milliseconds) => Integer(milliseconds);

  /// [value] as an [Integer] holding its own midnight, UTC, in milliseconds
  /// since the Unix epoch.
  ///
  /// [Date] carries no time of day at all, so unlike [timestamp] there is
  /// nothing to lose or disagree about in converting it: the same calendar
  /// date reads back on every device, in every time zone. Read one back
  /// with `asDate`.
  static DatabaseType date(Date value) => Integer(value.toDateTime().millisecondsSinceEpoch);

  /// [value] as a [Varchar] holding its JSON form.
  ///
  /// Stored as JSON rather than as a sortable integer, the way [date] and
  /// [timestamp] are: a bare time of day only sorts correctly against
  /// another in the same time zone, and [Time.utcOffset] makes that not
  /// always true, so nothing here pretends otherwise by picking a single
  /// sortable encoding.
  static DatabaseType time(Time value) => Varchar(jsonEncode(value.toJson()));

  /// [value] as a [Varchar] holding its own name.
  ///
  /// The same convention [ValkeryStorage] already uses for its own
  /// [Valkery.enum_]: stored by name rather than by index, so reordering a
  /// project's own enum never silently changes what an existing row reads
  /// back as. Read one back with `asEnum`, given the same enum's own
  /// `values`.
  static DatabaseType enum_(Enum value) => Varchar(value.name);

  /// [value] as a [Varchar] holding its JSON form — meant for a list whose
  /// elements are already native JSON values: an [int], a [double], a
  /// [String], a [bool], a `Map<String, dynamic>`, or `null`.
  ///
  /// For a list of a project's own type instead, one that knows its own
  /// `toJson`, reach for [ListJson] — the same way [Json] covers a single
  /// value of one.
  static DatabaseType list<T>(List<T> value) => Varchar(jsonEncode(value));

  /// A new, randomly generated UUID (version 4), as a [Varchar].
  ///
  /// Backed by [Uuid]'s own default random source, cryptographically strong
  /// rather than [Random]'s: two calls landing in the same millisecond,
  /// across however many concurrent inserts, still practically never
  /// collide, which a hand-rolled generator seeded from the clock could not
  /// promise.
  static DatabaseType uuid() => Varchar(_uuidGenerator.v4());

  /// [value] as a [Varchar] holding its JSON form, `{"lat": ..., "lng": ...}`.
  ///
  /// SQLite has no geometric storage class either — unlike a timestamp or a
  /// UUID, a point has no single native representation any driver already
  /// agrees on, so this picks the plainest one rather than a binary format
  /// only this package could read back.
  static DatabaseType point(Location value) => Varchar(jsonEncode(value.toJson()));

  /// [value] as a [Varchar] holding its JSON form.
  static DatabaseType line(LocationLine value) => Varchar(jsonEncode(value.toJson()));

  /// [value] as a [Varchar] holding its JSON form.
  static DatabaseType segment(LocationSegment value) => Varchar(jsonEncode(value.toJson()));

  /// [value] as a [Varchar] holding its JSON form.
  static DatabaseType box(LocationBox value) => Varchar(jsonEncode(value.toJson()));

  /// [value] as a [Varchar] holding its JSON form.
  static DatabaseType path(LocationPath value) => Varchar(jsonEncode(value.toJson()));

  /// [value] as a [Varchar] holding its JSON form.
  static DatabaseType polygon(LocationPolygon value) => Varchar(jsonEncode(value.toJson()));

  /// [value] as a [Varchar] holding its JSON form.
  static DatabaseType circle(LocationCircle value) => Varchar(jsonEncode(value.toJson()));

  /// [value] as a [Varchar] holding its two bounds: an [IntervalBounds.num]
  /// stores them exactly as given, an [IntervalBounds.datetime] stores each
  /// as its millisecond offset from the Unix epoch, in UTC.
  ///
  /// Read one back with `asNumberBounds` or `asDateTimeBounds`, whichever
  /// kind it was written as.
  static DatabaseType interval(IntervalBounds value) => switch (value) {
    NumberBounds(:final start, :final end) => Varchar(jsonEncode({'start': start, 'end': end})),
    DateTimeBounds(:final start, :final end) => Varchar(
      jsonEncode({'start': start.toUtc().millisecondsSinceEpoch, 'end': end.toUtc().millisecondsSinceEpoch}),
    ),
  };

  /// [value] as a [Varchar] holding its own [RangeSubtype], bounds and
  /// inclusivity: a [RangeBounds.num] stores its two ends exactly as given,
  /// a [RangeBounds.datetime] stores each as its millisecond offset from the
  /// Unix epoch, in UTC — [RangeSubtype.timestamp] and
  /// [RangeSubtype.timestamptz] are not told apart beyond that, and
  /// [RangeSubtype.date] carries whatever time of day a project's own
  /// [DateTime] already had, midnight or not.
  ///
  /// Read one back with `asNumberRange` or `asDateTimeRange`, whichever kind
  /// it was written as.
  static DatabaseType range(RangeBounds value) => switch (value) {
    NumberRangeBounds(:final lower, :final upper) => Varchar(
      jsonEncode({
        'subtype': value.subtype.name,
        'lower': lower,
        'upper': upper,
        'lowerInclusive': value.lowerInclusive,
        'upperInclusive': value.upperInclusive,
      }),
    ),
    DateTimeRangeBounds(:final lower, :final upper) => Varchar(
      jsonEncode({
        'subtype': value.subtype.name,
        'lower': lower?.toUtc().millisecondsSinceEpoch,
        'upper': upper?.toUtc().millisecondsSinceEpoch,
        'lowerInclusive': value.lowerInclusive,
        'upperInclusive': value.upperInclusive,
      }),
    ),
  };

  /// This value in the native shape sqflite itself accepts and hands back.
  Object? _toNative();

  Map<String, dynamic> _decodeJson(String shape) {
    if (this case Varchar(value: final stored)) return jsonDecode(stored) as Map<String, dynamic>;
    throw StateError('$this is not a $shape.');
  }

  T _asJson<T>(T Function(Map<String, dynamic> json) fromJson, String shape) => fromJson(_decodeJson(shape));
}

final Uuid _uuidGenerator = const Uuid();

/// The absence of a value — SQL `NULL`.
final class Nil extends DatabaseType {
  /// SQL `NULL`. Prefer [DatabaseType.nil] over calling this directly.
  const Nil();

  @override
  Object? _toNative() => null;

  @override
  List<Object?> get props => const [];

  @override
  String toString() => 'DatabaseType.nil()';
}

/// A signed integer, up to 64 bits.
final class Integer extends DatabaseType {
  /// Wraps [value]. Prefer [DatabaseType.integer] over calling this
  /// directly.
  const Integer(this.value);

  /// The wrapped integer.
  final int value;

  @override
  Object? _toNative() => value;

  @override
  List<Object?> get props => [value];

  @override
  String toString() => 'DatabaseType.integer($value)';
}

/// A floating point value.
final class Real extends DatabaseType {
  /// Wraps [value]. Prefer [DatabaseType.real] over calling this directly.
  const Real(this.value);

  /// The wrapped floating point value.
  final double value;

  @override
  Object? _toNative() => value;

  @override
  List<Object?> get props => [value];

  @override
  String toString() => 'DatabaseType.real($value)';
}

/// UTF-8 text.
final class Varchar extends DatabaseType {
  /// Wraps [value]. Prefer [DatabaseType.varchar] over calling this
  /// directly.
  const Varchar(this.value);

  /// The wrapped text.
  final String value;

  @override
  Object? _toNative() => value;

  @override
  List<Object?> get props => [value];

  @override
  String toString() => 'DatabaseType.varchar($value)';
}

/// Raw bytes, stored exactly as given.
final class Blob extends DatabaseType {
  /// Wraps [value]. Prefer [DatabaseType.blob] over calling this directly.
  const Blob(this.value);

  /// The wrapped bytes.
  final Uint8List value;

  @override
  Object? _toNative() => value;

  @override
  List<Object?> get props => [value];

  @override
  String toString() => 'DatabaseType.blob(${value.length} byte(s))';
}

/// One row, exactly as [LocalDatabase] reads one back or writes one out:
/// column name to [DatabaseType]. What a column holds, and what its name
/// means, is entirely the caller's own schema.
typedef DatabaseRow = Map<String, DatabaseType>;

/// Wraps whatever sqflite itself already handed back for one column.
///
/// Throws an [ArgumentError] if [native] is not one of the native types
/// sqflite hands back — which should never happen for a value this same
/// library wrote through `_toNative` in the first place.
DatabaseType _fromNative(Object? native) => switch (native) {
  null => const Nil(),
  final int value => Integer(value),
  final double value => Real(value),
  final String value => Varchar(value),
  final Uint8List value => Blob(value),
  _ => throw ArgumentError.value(native, 'native', 'not a SQLite storage class'),
};

Map<String, Object?> _toNativeRow(DatabaseRow row) => row.map((column, value) => MapEntry(column, value._toNative()));

DatabaseRow _fromNativeRow(Map<String, Object?> row) =>
    row.map((column, value) => MapEntry(column, _fromNative(value)));

List<Object?>? _toNativeArgs(List<DatabaseType>? arguments) => arguments?.map((value) => value._toNative()).toList();
