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

import 'dart:typed_data';

import 'package:fiber_pylon/fiber_pylon.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

enum Season { spring, summer, autumn, winter }

final class CartItem {
  const CartItem({required this.sku, required this.quantity});

  final String sku;
  final int quantity;

  static CartItem fromJson(Map<String, dynamic> json) =>
      CartItem(sku: json['sku'] as String, quantity: json['quantity'] as int);

  Map<String, dynamic> toJson() => {'sku': sku, 'quantity': quantity};
}

void main() {
  group('Value', () {
    test('boolean round-trips through asBoolean', () {
      expect(Value.boolean(true).asBoolean, isTrue);
      expect(Value.boolean(false).asBoolean, isFalse);
    });

    test('asBoolean throws on a value that never was one', () {
      expect(() => const Value.varchar('nope').asBoolean, throwsStateError);
    });

    test('timestamp round-trips through asDateTime, always in UTC', () {
      final now = DateTime.now();

      final stored = Value.timestamp(now.millisecondsSinceEpoch);

      expect(stored, isA<Integer>());
      expect(stored.asDateTime.isUtc, isTrue);
      expect(stored.asDateTime.millisecondsSinceEpoch, now.toUtc().millisecondsSinceEpoch);
    });

    test('asDateTime throws on a value that never was a timestamp', () {
      expect(() => const Value.varchar('nope').asDateTime, throwsStateError);
    });

    test('date round-trips through asDate, regardless of time zone', () {
      const bastilleDay = Date(year: 2026, month: 7, day: 14);

      final stored = Value.date(bastilleDay);

      expect(stored, isA<Integer>());
      expect(stored.asDate, bastilleDay);
    });

    test('asDate throws on a value that never was a date', () {
      expect(() => const Value.varchar('nope').asDate, throwsStateError);
    });

    test('time round-trips through asTime, with no time zone', () {
      const lunch = Time(hour: 12, minute: 30, second: 15, millisecond: 500);

      final stored = Value.time(lunch);

      expect(stored, isA<Varchar>());
      expect(stored.asTime, lunch);
      expect(stored.asTime.utcOffset, isNull);
    });

    test('time round-trips through asTime, carrying its own time zone', () {
      const noonInParis = Time(hour: 12, minute: 0, utcOffset: Duration(hours: 1));

      final decoded = Value.time(noonInParis).asTime;

      expect(decoded, noonInParis);
      expect(decoded.utcOffset, const Duration(hours: 1));
    });

    test('time is stored as fixed-width text, with its offset when it has one', () {
      expect(Value.time(const Time(hour: 9, minute: 5)).value, '09:05:00.000');
      expect(Value.time(const Time(hour: 23, minute: 59, second: 58, millisecond: 7)).value, '23:59:58.007');
      expect(
        Value.time(const Time(hour: 12, minute: 0, utcOffset: Duration(hours: 1))).value,
        '12:00:00.000+01:00',
      );
      expect(
        Value.time(const Time(hour: 12, minute: 0, utcOffset: Duration(hours: -3, minutes: -30))).value,
        '12:00:00.000-03:30',
      );
    });

    test('time round-trips a negative offset with minutes', () {
      const time = Time(hour: 12, minute: 0, utcOffset: Duration(hours: -3, minutes: -30));

      expect(Value.time(time).asTime, time);
    });

    test('the text of two times without an offset sorts the way the times do', () {
      final texts = [
        for (final time in const [
          Time(hour: 10, minute: 0),
          Time(hour: 9, minute: 30),
          Time(hour: 9, minute: 0, millisecond: 1),
          Time(hour: 0, minute: 0),
        ])
          Value.time(time).value,
      ]..sort();

      expect(texts, ['00:00:00.000', '09:00:00.001', '09:30:00.000', '10:00:00.000']);
    });

    test('asTime throws a FormatException on text that is not a time of day', () {
      expect(() => const Value.varchar('9:30').asTime, throwsFormatException);
      expect(() => const Value.varchar('{"hour":9}').asTime, throwsFormatException);
    });

    test('a whole number is written the same text whether it was an int or a double', () {
      expect(
        Value.interval(const IntervalBounds.num(start: 3, end: 4)),
        Value.interval(const IntervalBounds.num(start: 3.0, end: 4.0)),
      );
      expect(
        Value.range(const RangeBounds.num(subtype: NumberRangeSubtype.integer, lower: 1, upper: 10)),
        Value.range(const RangeBounds.num(subtype: NumberRangeSubtype.integer, lower: 1.0, upper: 10.0)),
      );
      expect(
        Value.interval(const IntervalBounds.num(start: 3, end: 4.5)) ==
            Value.interval(const IntervalBounds.num(start: 3, end: 4.25)),
        isFalse,
      );
    });

    test('asTime throws on a value that never was a time', () {
      expect(() => const Value.integer(1).asTime, throwsStateError);
    });

    test('enum_ round-trips through asEnum, by name rather than by index', () {
      final stored = Value.enum_(Season.summer);

      expect(stored, isA<Varchar>());
      expect(stored.value, 'summer');
      expect(stored.asEnum(Season.values), Season.summer);
    });

    test('asEnum throws when no member matches by name', () {
      expect(() => const Value.varchar('monsoon').asEnum(Season.values), throwsArgumentError);
    });

    test('asEnum throws on a value that never was an enum', () {
      expect(() => const Value.integer(1).asEnum(Season.values), throwsStateError);
    });

    test('list round-trips a list of int, double, String and bool', () {
      expect(Value.list(const [1, 2, 3]).asList<int>(), [1, 2, 3]);
      expect(Value.list(const [1.5, 2.5]).asList<double>(), [1.5, 2.5]);
      expect(Value.list(const ['a', 'b']).asList<String>(), ['a', 'b']);
      expect(Value.list(const [true, false]).asList<bool>(), [true, false]);
    });

    test('list round-trips a list of maps', () {
      const maps = [
        {'sku': 'mug-01'},
        {'sku': 'mug-02'},
      ];

      expect(Value.list(maps).asList<Map<String, dynamic>>(), maps);
    });

    test('asList throws on a value that never was a list', () {
      expect(() => const Value.integer(1).asList<int>(), throwsStateError);
    });

    test('randomUuid generates a well-formed version 4 identifier', () {
      final value = Value.randomUuid();

      expect(value.value, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });

    test('randomUuid never repeats across a burst of rapid generation', () {
      final generated = {for (var i = 0; i < 2000; i++) Value.randomUuid().value};

      expect(generated, hasLength(2000));
    });

    test('point round-trips through asPoint', () {
      const origin = Location(lat: 48.8566, lng: 2.3522);

      final stored = Value.point(origin);

      expect(stored, isA<Varchar>());
      expect(stored.asPoint, origin);
    });

    test('asPoint throws on a value that never was a point', () {
      expect(() => const Value.integer(1).asPoint, throwsStateError);
    });

    test('line round-trips through asLine', () {
      const line = LocationLine(a: Location(lat: 48.85, lng: 2.35), b: Location(lat: 45.75, lng: 4.85));

      expect(Value.line(line).asLine, line);
    });

    test('asLine throws on a value that never was a line', () {
      expect(() => const Value.integer(1).asLine, throwsStateError);
    });

    test('segment round-trips through asSegment', () {
      const segment = LocationSegment(a: Location(lat: 48.85, lng: 2.35), b: Location(lat: 45.75, lng: 4.85));

      expect(Value.segment(segment).asSegment, segment);
    });

    test('asSegment throws on a value that never was a segment', () {
      expect(() => const Value.integer(1).asSegment, throwsStateError);
    });

    test('box round-trips through asBox', () {
      const box = LocationBox(low: Location(lat: 45.0, lng: 2.0), high: Location(lat: 49.0, lng: 5.0));

      expect(Value.box(box).asBox, box);
    });

    test('asBox throws on a value that never was a box', () {
      expect(() => const Value.integer(1).asBox, throwsStateError);
    });

    test('path round-trips through asPath, open or closed', () {
      const open = LocationPath(points: [Location(lat: 0, lng: 0), Location(lat: 1, lng: 1)]);
      const closed = LocationPath(points: [Location(lat: 0, lng: 0), Location(lat: 1, lng: 1)], closed: true);

      expect(Value.path(open).asPath, open);
      expect(Value.path(closed).asPath, closed);
      expect(Value.path(open).asPath.closed, isFalse);
      expect(Value.path(closed).asPath.closed, isTrue);
    });

    test('asPath throws on a value that never was a path', () {
      expect(() => const Value.integer(1).asPath, throwsStateError);
    });

    test('polygon round-trips through asPolygon', () {
      const polygon = LocationPolygon(
        points: [Location(lat: 0, lng: 0), Location(lat: 1, lng: 0), Location(lat: 0, lng: 1)],
      );

      expect(Value.polygon(polygon).asPolygon, polygon);
    });

    test('asPolygon throws on a value that never was a polygon', () {
      expect(() => const Value.integer(1).asPolygon, throwsStateError);
    });

    test('circle round-trips through asCircle', () {
      const circle = LocationCircle(center: Location(lat: 48.85, lng: 2.35), radius: 1500);

      expect(Value.circle(circle).asCircle, circle);
    });

    test('asCircle throws on a value that never was a circle', () {
      expect(() => const Value.integer(1).asCircle, throwsStateError);
    });

    test('interval of numbers round-trips through asNumberBounds', () {
      const bounds = IntervalBounds.num(start: 3, end: 4.5);

      final decoded = Value.interval(bounds).asNumberBounds;

      expect(decoded, bounds);
      expect(decoded.start, 3);
      expect(decoded.end, 4.5);
    });

    test('interval of dates round-trips through asDateTimeBounds, always in UTC', () {
      final start = DateTime(2026);
      final end = DateTime(2026, 6);

      final decoded = Value.interval(IntervalBounds.datetime(start: start, end: end)).asDateTimeBounds;

      expect(decoded.start.isUtc, isTrue);
      expect(decoded.end.isUtc, isTrue);
      expect(decoded.start.millisecondsSinceEpoch, start.toUtc().millisecondsSinceEpoch);
      expect(decoded.end.millisecondsSinceEpoch, end.toUtc().millisecondsSinceEpoch);
    });

    test('a number interval and a date interval are told apart by their factory', () {
      expect(const IntervalBounds.num(start: 1, end: 2), isA<NumberBounds>());
      expect(IntervalBounds.datetime(start: DateTime(2026), end: DateTime(2027)), isA<DateTimeBounds>());
    });

    test('asNumberBounds and asDateTimeBounds throw on a value that never was an interval', () {
      expect(() => const Value.integer(1).asNumberBounds, throwsStateError);
      expect(() => const Value.integer(1).asDateTimeBounds, throwsStateError);
    });

    test('range of numbers round-trips through asNumberRange, with its default bounds', () {
      const bounds = RangeBounds.num(subtype: NumberRangeSubtype.integer, lower: 1, upper: 10);

      final decoded = Value.range(bounds).asNumberRange;

      expect(decoded, bounds);
      expect(decoded.subtype, NumberRangeSubtype.integer);
      expect(decoded.lower, 1);
      expect(decoded.upper, 10);
      expect(decoded.lowerInclusive, isTrue);
      expect(decoded.upperInclusive, isFalse);
    });

    test('range of numbers round-trips an unbounded side and explicit inclusivity', () {
      const bounds = RangeBounds.num(
        subtype: NumberRangeSubtype.numeric,
        upper: 99.5,
        lowerInclusive: false,
        upperInclusive: true,
      );

      final decoded = Value.range(bounds).asNumberRange;

      expect(decoded.lower, isNull);
      expect(decoded.upper, 99.5);
      expect(decoded.lowerInclusive, isFalse);
      expect(decoded.upperInclusive, isTrue);
    });

    test('range of dates round-trips through asDateTimeRange, always in UTC', () {
      final lower = DateTime(2026);
      final upper = DateTime(2027);

      final decoded = Value.range(
        RangeBounds.datetime(subtype: DateTimeRangeSubtype.timestamptz, lower: lower, upper: upper),
      ).asDateTimeRange;

      expect(decoded.subtype, DateTimeRangeSubtype.timestamptz);
      expect(decoded.lower!.isUtc, isTrue);
      expect(decoded.lower!.millisecondsSinceEpoch, lower.toUtc().millisecondsSinceEpoch);
      expect(decoded.upper!.millisecondsSinceEpoch, upper.toUtc().millisecondsSinceEpoch);
    });

    test('range of dates round-trips an unbounded side', () {
      final lower = DateTime(2026);

      final decoded = Value.range(
        RangeBounds.datetime(subtype: DateTimeRangeSubtype.timestamp, lower: lower),
      ).asDateTimeRange;

      expect(decoded.lower, isNotNull);
      expect(decoded.upper, isNull);
    });

    test('range of calendar dates round-trips through asDateRange, with no time of day to lose', () {
      const lower = Date(year: 2026, month: 7, day: 14);
      const upper = Date(year: 2026, month: 8, day: 31);

      final decoded = Value.range(const RangeBounds.date(lower: lower, upper: upper)).asDateRange;

      expect(decoded, const RangeBounds.date(lower: lower, upper: upper));
      expect(decoded.lower, lower);
      expect(decoded.upper, upper);
    });

    test('range of calendar dates round-trips an unbounded side and explicit inclusivity', () {
      const upper = Date(year: 2026, month: 8, day: 31);

      final decoded = Value.range(const RangeBounds.date(upper: upper, upperInclusive: true)).asDateRange;

      expect(decoded.lower, isNull);
      expect(decoded.upper, upper);
      expect(decoded.lowerInclusive, isTrue);
      expect(decoded.upperInclusive, isTrue);
    });

    test('a number range, a date time range and a date range are told apart by their factory', () {
      expect(const RangeBounds.num(subtype: NumberRangeSubtype.integer), isA<NumberRangeBounds>());
      expect(const RangeBounds.datetime(subtype: DateTimeRangeSubtype.timestamp), isA<DateTimeRangeBounds>());
      expect(const RangeBounds.date(), isA<DateRangeBounds>());
    });

    test('asNumberRange, asDateTimeRange and asDateRange throw on a value that never was a range', () {
      expect(() => const Value.integer(1).asNumberRange, throwsStateError);
      expect(() => const Value.integer(1).asDateTimeRange, throwsStateError);
      expect(() => const Value.integer(1).asDateRange, throwsStateError);
    });
  });

  group('NativeDecoding', () {
    test('asInt, asDouble, asString and asBytes read back the storage class they were written as', () {
      expect(const Value.integer(42).asInt, 42);
      expect(const Value.real(1.5).asDouble, 1.5);
      expect(const Value.varchar('hello').asString, 'hello');
      expect(Value.blob(Uint8List.fromList([1, 2, 3])).asBytes, [1, 2, 3]);
    });

    test('each one throws a StateError naming the value when the storage class differs', () {
      expect(() => const Value.varchar('nope').asInt, throwsStateError);
      expect(() => const Value.varchar('1.5').asDouble, throwsStateError);
      expect(() => const Value.integer(1).asString, throwsStateError);
      expect(() => const Value.integer(1).asBytes, throwsStateError);
      expect(() => const Value.nil().asInt, throwsStateError);
    });

    test('a convention factory answers the storage class it is stored as, by its own static type', () {
      final Integer flag = Value.boolean(true);
      final Integer moment = Value.timestamp(0);
      final Integer day = Value.date(const Date(year: 2026, month: 7, day: 14));
      final Varchar season = Value.enum_(Season.summer);
      final Varchar shape = Value.point(const Location(lat: 0, lng: 0));

      expect([flag.value, moment.value, day.value], [1, 0, 1783987200000]);
      expect([season.value, shape.value], ['summer', '{"lat":0.0,"lng":0.0}']);
    });
  });

  group('UuidDecoding', () {
    test('a given UUID round-trips through asUuid, in its canonical lower-case form', () {
      final id = UuidValue.fromString('123E4567-E89B-42D3-A456-426614174000');

      final stored = Value.uuid(id);

      expect(stored.value, '123e4567-e89b-42d3-a456-426614174000');
      expect(stored.asUuid, id);
    });

    test('a generated UUID can be read back as the value it holds', () {
      final generated = Value.randomUuid();

      expect(generated.asUuid.uuid, generated.value);
    });

    test('asUuid throws a StateError on a value that never was text', () {
      expect(() => const Value.integer(1).asUuid, throwsStateError);
    });

    test('asUuid throws a FormatException on text that is not a UUID', () {
      expect(() => const Value.varchar('not-a-uuid').asUuid, throwsFormatException);
    });
  });

  group('value invariants', () {
    Date date(int year, int month, int day) => Date(year: year, month: month, day: day);
    Time time(int hour, int minute, int second, int millisecond) =>
        Time(hour: hour, minute: minute, second: second, millisecond: millisecond);
    Location location(double lat, double lng) => Location(lat: lat, lng: lng);

    test('Date refuses a month outside 1 through 12', () {
      expect(() => date(2026, 0, 1), throwsA(isA<AssertionError>()));
      expect(() => date(2026, 13, 1), throwsA(isA<AssertionError>()));
    });

    test('Date refuses a day the month does not have, leap years included', () {
      expect(() => date(2026, 4, 31), throwsA(isA<AssertionError>()));
      expect(() => date(2026, 2, 29), throwsA(isA<AssertionError>()));
      expect(() => date(1900, 2, 29), throwsA(isA<AssertionError>()));
      expect(() => date(2026, 1, 0), throwsA(isA<AssertionError>()));
    });

    test('Date accepts the last day of every kind of month', () {
      expect(date(2024, 2, 29).day, 29);
      expect(date(2000, 2, 29).day, 29);
      expect(date(2026, 2, 28).day, 28);
      expect(date(2026, 4, 30).day, 30);
      expect(date(2026, 12, 31).day, 31);
    });

    test('Time refuses a field outside the range its own documentation gives', () {
      expect(() => time(24, 0, 0, 0), throwsA(isA<AssertionError>()));
      expect(() => time(0, 60, 0, 0), throwsA(isA<AssertionError>()));
      expect(() => time(0, 0, 60, 0), throwsA(isA<AssertionError>()));
      expect(() => time(0, 0, 0, 1000), throwsA(isA<AssertionError>()));
      expect(() => time(-1, 0, 0, 0), throwsA(isA<AssertionError>()));
      expect(time(23, 59, 59, 999).hour, 23);
    });

    test('Location refuses a latitude or a longitude outside the globe, and a NaN', () {
      expect(() => location(90.1, 0), throwsA(isA<AssertionError>()));
      expect(() => location(-90.1, 0), throwsA(isA<AssertionError>()));
      expect(() => location(0, 180.1), throwsA(isA<AssertionError>()));
      expect(() => location(0, -180.1), throwsA(isA<AssertionError>()));
      expect(() => location(double.nan, 0), throwsA(isA<AssertionError>()));
      expect(location(90, -180).lat, 90);
    });

    test('LocationCircle refuses a negative radius', () {
      final center = location(0, 0);

      expect(() => LocationCircle(center: center, radius: -1), throwsA(isA<AssertionError>()));
      expect(LocationCircle(center: center, radius: 0).radius, 0);
    });

    test('Location reads a coordinate JSON wrote as a whole number', () {
      final decoded = Location.fromJson({'lat': 48, 'lng': 2});

      expect(decoded, const Location(lat: 48, lng: 2));
    });
  });

  group('Json', () {
    const codec = Json<CartItem>(fromJson: CartItem.fromJson, toJson: _cartItemToJson);

    test('encodes into a varchar and decodes back the same value', () {
      const item = CartItem(sku: 'mug-01', quantity: 2);

      final encoded = codec.encode(item);
      final decoded = codec.decode(encoded);

      expect(encoded, isA<Varchar>());
      expect(decoded.sku, item.sku);
      expect(decoded.quantity, item.quantity);
    });

    test('decode throws on a value that never was JSON', () {
      expect(() => codec.decode(const Value.integer(1)), throwsStateError);
    });
  });

  group('ListJson', () {
    const codec = ListJson<CartItem>(fromJson: CartItem.fromJson, toJson: _cartItemToJson);

    test('encodes into a varchar and decodes back the same list', () {
      const items = [CartItem(sku: 'mug-01', quantity: 2), CartItem(sku: 'mug-02', quantity: 1)];

      final encoded = codec.encode(items);
      final decoded = codec.decode(encoded);

      expect(encoded, isA<Varchar>());
      expect(decoded.map((item) => item.sku), items.map((item) => item.sku));
      expect(decoded.map((item) => item.quantity), items.map((item) => item.quantity));
    });

    test('decode throws on a value that never was JSON', () {
      expect(() => codec.decode(const Value.integer(1)), throwsStateError);
    });
  });
}

Map<String, dynamic> _cartItemToJson(CartItem value) => value.toJson();
