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

import 'package:fiber_pylon/fiber_pylon.dart';
import 'package:flutter_test/flutter_test.dart';

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
  group('DatabaseType', () {
    test('boolean round-trips through asBoolean', () {
      expect(DatabaseType.boolean(true).asBoolean, isTrue);
      expect(DatabaseType.boolean(false).asBoolean, isFalse);
    });

    test('asBoolean throws on a value that never was one', () {
      expect(() => const DatabaseType.varchar('nope').asBoolean, throwsStateError);
    });

    test('timestamp round-trips through asDateTime, always in UTC', () {
      final now = DateTime.now();

      final stored = DatabaseType.timestamp(now.millisecondsSinceEpoch);

      expect(stored, isA<Integer>());
      expect(stored.asDateTime.isUtc, isTrue);
      expect(stored.asDateTime.millisecondsSinceEpoch, now.toUtc().millisecondsSinceEpoch);
    });

    test('asDateTime throws on a value that never was a timestamp', () {
      expect(() => const DatabaseType.varchar('nope').asDateTime, throwsStateError);
    });

    test('date round-trips through asDate, regardless of time zone', () {
      const bastilleDay = Date(year: 2026, month: 7, day: 14);

      final stored = DatabaseType.date(bastilleDay);

      expect(stored, isA<Integer>());
      expect(stored.asDate, bastilleDay);
    });

    test('asDate throws on a value that never was a date', () {
      expect(() => const DatabaseType.varchar('nope').asDate, throwsStateError);
    });

    test('time round-trips through asTime, with no time zone', () {
      const lunch = Time(hour: 12, minute: 30, second: 15, millisecond: 500);

      final stored = DatabaseType.time(lunch);

      expect(stored, isA<Varchar>());
      expect(stored.asTime, lunch);
      expect(stored.asTime.utcOffset, isNull);
    });

    test('time round-trips through asTime, carrying its own time zone', () {
      const noonInParis = Time(hour: 12, minute: 0, utcOffset: Duration(hours: 1));

      final decoded = DatabaseType.time(noonInParis).asTime;

      expect(decoded, noonInParis);
      expect(decoded.utcOffset, const Duration(hours: 1));
    });

    test('asTime throws on a value that never was a time', () {
      expect(() => const DatabaseType.integer(1).asTime, throwsStateError);
    });

    test('enum_ round-trips through asEnum, by name rather than by index', () {
      final stored = DatabaseType.enum_(Season.summer);

      expect(stored, isA<Varchar>());
      expect((stored as Varchar).value, 'summer');
      expect(stored.asEnum(Season.values), Season.summer);
    });

    test('asEnum throws when no member matches by name', () {
      expect(() => const DatabaseType.varchar('monsoon').asEnum(Season.values), throwsArgumentError);
    });

    test('asEnum throws on a value that never was an enum', () {
      expect(() => const DatabaseType.integer(1).asEnum(Season.values), throwsStateError);
    });

    test('list round-trips a list of int, double, String and bool', () {
      expect(DatabaseType.list(const [1, 2, 3]).asList<int>(), [1, 2, 3]);
      expect(DatabaseType.list(const [1.5, 2.5]).asList<double>(), [1.5, 2.5]);
      expect(DatabaseType.list(const ['a', 'b']).asList<String>(), ['a', 'b']);
      expect(DatabaseType.list(const [true, false]).asList<bool>(), [true, false]);
    });

    test('list round-trips a list of maps', () {
      const maps = [
        {'sku': 'mug-01'},
        {'sku': 'mug-02'},
      ];

      expect(DatabaseType.list(maps).asList<Map<String, dynamic>>(), maps);
    });

    test('asList throws on a value that never was a list', () {
      expect(() => const DatabaseType.integer(1).asList<int>(), throwsStateError);
    });

    test('uuid generates a well-formed version 4 identifier', () {
      final value = DatabaseType.uuid();

      expect(value, isA<Varchar>());
      expect(
        (value as Varchar).value,
        matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
      );
    });

    test('uuid never repeats across a burst of rapid generation', () {
      final generated = {for (var i = 0; i < 2000; i++) (DatabaseType.uuid() as Varchar).value};

      expect(generated, hasLength(2000));
    });

    test('point round-trips through asPoint', () {
      const origin = Location(lat: 48.8566, lng: 2.3522);

      final stored = DatabaseType.point(origin);

      expect(stored, isA<Varchar>());
      expect(stored.asPoint, origin);
    });

    test('asPoint throws on a value that never was a point', () {
      expect(() => const DatabaseType.integer(1).asPoint, throwsStateError);
    });

    test('line round-trips through asLine', () {
      const line = LocationLine(a: Location(lat: 48.85, lng: 2.35), b: Location(lat: 45.75, lng: 4.85));

      expect(DatabaseType.line(line).asLine, line);
    });

    test('asLine throws on a value that never was a line', () {
      expect(() => const DatabaseType.integer(1).asLine, throwsStateError);
    });

    test('segment round-trips through asSegment', () {
      const segment = LocationSegment(a: Location(lat: 48.85, lng: 2.35), b: Location(lat: 45.75, lng: 4.85));

      expect(DatabaseType.segment(segment).asSegment, segment);
    });

    test('asSegment throws on a value that never was a segment', () {
      expect(() => const DatabaseType.integer(1).asSegment, throwsStateError);
    });

    test('box round-trips through asBox', () {
      const box = LocationBox(low: Location(lat: 45.0, lng: 2.0), high: Location(lat: 49.0, lng: 5.0));

      expect(DatabaseType.box(box).asBox, box);
    });

    test('asBox throws on a value that never was a box', () {
      expect(() => const DatabaseType.integer(1).asBox, throwsStateError);
    });

    test('path round-trips through asPath, open or closed', () {
      const open = LocationPath(points: [Location(lat: 0, lng: 0), Location(lat: 1, lng: 1)]);
      const closed = LocationPath(points: [Location(lat: 0, lng: 0), Location(lat: 1, lng: 1)], closed: true);

      expect(DatabaseType.path(open).asPath, open);
      expect(DatabaseType.path(closed).asPath, closed);
      expect(DatabaseType.path(open).asPath.closed, isFalse);
      expect(DatabaseType.path(closed).asPath.closed, isTrue);
    });

    test('asPath throws on a value that never was a path', () {
      expect(() => const DatabaseType.integer(1).asPath, throwsStateError);
    });

    test('polygon round-trips through asPolygon', () {
      const polygon = LocationPolygon(
        points: [Location(lat: 0, lng: 0), Location(lat: 1, lng: 0), Location(lat: 0, lng: 1)],
      );

      expect(DatabaseType.polygon(polygon).asPolygon, polygon);
    });

    test('asPolygon throws on a value that never was a polygon', () {
      expect(() => const DatabaseType.integer(1).asPolygon, throwsStateError);
    });

    test('circle round-trips through asCircle', () {
      const circle = LocationCircle(center: Location(lat: 48.85, lng: 2.35), radius: 1500);

      expect(DatabaseType.circle(circle).asCircle, circle);
    });

    test('asCircle throws on a value that never was a circle', () {
      expect(() => const DatabaseType.integer(1).asCircle, throwsStateError);
    });

    test('interval of numbers round-trips through asNumberBounds', () {
      const bounds = IntervalBounds.num(start: 3, end: 4.5);

      final decoded = DatabaseType.interval(bounds).asNumberBounds;

      expect(decoded, bounds);
      expect(decoded.start, 3);
      expect(decoded.end, 4.5);
    });

    test('interval of dates round-trips through asDateTimeBounds, always in UTC', () {
      final start = DateTime(2026);
      final end = DateTime(2026, 6);

      final decoded = DatabaseType.interval(IntervalBounds.datetime(start: start, end: end)).asDateTimeBounds;

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
      expect(() => const DatabaseType.integer(1).asNumberBounds, throwsStateError);
      expect(() => const DatabaseType.integer(1).asDateTimeBounds, throwsStateError);
    });

    test('range of numbers round-trips through asNumberRange, with its default bounds', () {
      const bounds = RangeBounds.num(subtype: RangeSubtype.integer, lower: 1, upper: 10);

      final decoded = DatabaseType.range(bounds).asNumberRange;

      expect(decoded, bounds);
      expect(decoded.subtype, RangeSubtype.integer);
      expect(decoded.lower, 1);
      expect(decoded.upper, 10);
      expect(decoded.lowerInclusive, isTrue);
      expect(decoded.upperInclusive, isFalse);
    });

    test('range of numbers round-trips an unbounded side and explicit inclusivity', () {
      const bounds = RangeBounds.num(
        subtype: RangeSubtype.numeric,
        upper: 99.5,
        lowerInclusive: false,
        upperInclusive: true,
      );

      final decoded = DatabaseType.range(bounds).asNumberRange;

      expect(decoded.lower, isNull);
      expect(decoded.upper, 99.5);
      expect(decoded.lowerInclusive, isFalse);
      expect(decoded.upperInclusive, isTrue);
    });

    test('range of dates round-trips through asDateTimeRange, always in UTC', () {
      final lower = DateTime(2026);
      final upper = DateTime(2027);

      final decoded = DatabaseType.range(
        RangeBounds.datetime(subtype: RangeSubtype.timestamptz, lower: lower, upper: upper),
      ).asDateTimeRange;

      expect(decoded.subtype, RangeSubtype.timestamptz);
      expect(decoded.lower!.isUtc, isTrue);
      expect(decoded.lower!.millisecondsSinceEpoch, lower.toUtc().millisecondsSinceEpoch);
      expect(decoded.upper!.millisecondsSinceEpoch, upper.toUtc().millisecondsSinceEpoch);
    });

    test('range of dates round-trips an unbounded side', () {
      final lower = DateTime(2026);

      final decoded = DatabaseType.range(
        RangeBounds.datetime(subtype: RangeSubtype.date, lower: lower),
      ).asDateTimeRange;

      expect(decoded.lower, isNotNull);
      expect(decoded.upper, isNull);
    });

    test('a number range and a date range are told apart by their factory', () {
      expect(const RangeBounds.num(subtype: RangeSubtype.integer), isA<NumberRangeBounds>());
      expect(const RangeBounds.datetime(subtype: RangeSubtype.date), isA<DateTimeRangeBounds>());
    });

    test('asNumberRange and asDateTimeRange throw on a value that never was a range', () {
      expect(() => const DatabaseType.integer(1).asNumberRange, throwsStateError);
      expect(() => const DatabaseType.integer(1).asDateTimeRange, throwsStateError);
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
      expect(() => codec.decode(const DatabaseType.integer(1)), throwsStateError);
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
      expect(() => codec.decode(const DatabaseType.integer(1)), throwsStateError);
    });
  });
}

Map<String, dynamic> _cartItemToJson(CartItem value) => value.toJson();
