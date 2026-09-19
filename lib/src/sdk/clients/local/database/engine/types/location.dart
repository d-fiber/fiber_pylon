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

/// Reads back a value written by [Value.point], [Value.line] or one of the other shape factories.
extension LocationDecoding on Value {
  /// This value as a [Location].
  ///
  /// Use it on a value written by [Value.point].
  ///
  /// Throws a [StateError] if this is not a [Varchar]. Throws a [FormatException] or a
  /// [TypeError] if its text is not what was written.
  Location get asPoint => _asJson(Location.fromJson, 'point');

  /// This value as a [LocationLine].
  ///
  /// Use it on a value written by [Value.line].
  ///
  /// Throws a [StateError] if this is not a [Varchar]. Throws a [FormatException] or a
  /// [TypeError] if its text is not what was written.
  LocationLine get asLine => _asJson(LocationLine.fromJson, 'line');

  /// This value as a [LocationSegment].
  ///
  /// Use it on a value written by [Value.segment].
  ///
  /// Throws a [StateError] if this is not a [Varchar]. Throws a [FormatException] or a
  /// [TypeError] if its text is not what was written.
  LocationSegment get asSegment => _asJson(LocationSegment.fromJson, 'segment');

  /// This value as a [LocationBox].
  ///
  /// Use it on a value written by [Value.box].
  ///
  /// Throws a [StateError] if this is not a [Varchar]. Throws a [FormatException] or a
  /// [TypeError] if its text is not what was written.
  LocationBox get asBox => _asJson(LocationBox.fromJson, 'box');

  /// This value as a [LocationPath].
  ///
  /// Use it on a value written by [Value.path].
  ///
  /// Throws a [StateError] if this is not a [Varchar]. Throws a [FormatException] or a
  /// [TypeError] if its text is not what was written.
  LocationPath get asPath => _asJson(LocationPath.fromJson, 'path');

  /// This value as a [LocationPolygon].
  ///
  /// Use it on a value written by [Value.polygon].
  ///
  /// Throws a [StateError] if this is not a [Varchar]. Throws a [FormatException] or a
  /// [TypeError] if its text is not what was written.
  LocationPolygon get asPolygon => _asJson(LocationPolygon.fromJson, 'polygon');

  /// This value as a [LocationCircle].
  ///
  /// Use it on a value written by [Value.circle].
  ///
  /// Throws a [StateError] if this is not a [Varchar]. Throws a [FormatException] or a
  /// [TypeError] if its text is not what was written.
  LocationCircle get asCircle => _asJson(LocationCircle.fromJson, 'circle');
}

/// A point on a map, as [Value.point] writes it and [LocationDecoding.asPoint] reads it.
final class Location extends Equatable {
  /// Creates a point at [lat] degrees of latitude and [lng] degrees of longitude.
  ///
  /// Asserts that both are inside the range given on their fields, which also
  /// refuses a `NaN`.
  const Location({required this.lat, required this.lng})
    : assert(lat >= -90 && lat <= 90, 'lat must be -90 through 90.'),
      assert(lng >= -180 && lng <= 180, 'lng must be -180 through 180.');

  /// The latitude in degrees, from -90 at the South Pole to 90 at the North Pole.
  final double lat;

  /// The longitude in degrees, from -180 to 180.
  final double lng;

  /// Creates a [Location] from the JSON object [Location.toJson] returns.
  factory Location.fromJson(Map<String, dynamic> json) =>
      Location(lat: (json['lat'] as num).toDouble(), lng: (json['lng'] as num).toDouble());

  /// The JSON object that [Location.fromJson] reads back.
  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};

  @override
  List<Object?> get props => [lat, lng];
}

/// A straight line extending infinitely in both directions through the points [a] and [b].
///
/// A line and a [LocationSegment] through the same two points are stored
/// identically, so only the accessor a project reads a value with, either
/// [LocationDecoding.asLine] or [LocationDecoding.asSegment], tells them apart.
final class LocationLine extends Equatable {
  /// Creates the line through [a] and [b].
  const LocationLine({required this.a, required this.b});

  /// One of the two points this line passes through.
  final Location a;

  /// The other point this line passes through.
  final Location b;

  /// Creates a [LocationLine] from the JSON object [LocationLine.toJson] returns.
  factory LocationLine.fromJson(Map<String, dynamic> json) => LocationLine(
    a: Location.fromJson(json['a'] as Map<String, dynamic>),
    b: Location.fromJson(json['b'] as Map<String, dynamic>),
  );

  /// The JSON object that [LocationLine.fromJson] reads back.
  Map<String, dynamic> toJson() => {'a': a.toJson(), 'b': b.toJson()};

  @override
  List<Object?> get props => [a, b];
}

/// A straight segment that stops at its two endpoints [a] and [b].
///
/// Unlike a [LocationLine], it does not continue past them.
final class LocationSegment extends Equatable {
  /// Creates the segment from [a] to [b].
  const LocationSegment({required this.a, required this.b});

  /// One end of this segment.
  final Location a;

  /// The other end of this segment.
  final Location b;

  /// Creates a [LocationSegment] from the JSON object [LocationSegment.toJson] returns.
  factory LocationSegment.fromJson(Map<String, dynamic> json) => LocationSegment(
    a: Location.fromJson(json['a'] as Map<String, dynamic>),
    b: Location.fromJson(json['b'] as Map<String, dynamic>),
  );

  /// The JSON object that [LocationSegment.fromJson] reads back.
  Map<String, dynamic> toJson() => {'a': a.toJson(), 'b': b.toJson()};

  @override
  List<Object?> get props => [a, b];
}

/// An axis-aligned rectangle, spanning from [low] to [high].
///
/// Nothing requires [low] to be the lesser corner, and nothing reorders the
/// corners: they read back as they were given.
final class LocationBox extends Equatable {
  /// Creates the rectangle spanning [low] to [high].
  const LocationBox({required this.low, required this.high});

  /// The first corner of this rectangle.
  final Location low;

  /// The corner opposite [low].
  final Location high;

  /// Creates a [LocationBox] from the JSON object [LocationBox.toJson] returns.
  factory LocationBox.fromJson(Map<String, dynamic> json) => LocationBox(
    low: Location.fromJson(json['low'] as Map<String, dynamic>),
    high: Location.fromJson(json['high'] as Map<String, dynamic>),
  );

  /// The JSON object that [LocationBox.fromJson] reads back.
  Map<String, dynamic> toJson() => {'low': low.toJson(), 'high': high.toJson()};

  @override
  List<Object?> get props => [low, high];
}

/// An ordered sequence of [points], either open or [closed] back to its first point.
final class LocationPath extends Equatable {
  /// Creates a path through [points], closed or open according to [closed].
  const LocationPath({required this.points, this.closed = false});

  /// The points this path passes through, in order.
  final List<Location> points;

  /// Whether this path loops its last point back to its first.
  final bool closed;

  /// Creates a [LocationPath] from the JSON object [LocationPath.toJson] returns.
  factory LocationPath.fromJson(Map<String, dynamic> json) => LocationPath(
    points: (json['points'] as List<dynamic>).map((point) => Location.fromJson(point as Map<String, dynamic>)).toList(),
    closed: json['closed'] as bool,
  );

  /// The JSON object that [LocationPath.fromJson] reads back.
  Map<String, dynamic> toJson() => {'points': points.map((point) => point.toJson()).toList(), 'closed': closed};

  @override
  List<Object?> get props => [points, closed];
}

/// A closed shape bounded by [points], its last point joined back to its first.
final class LocationPolygon extends Equatable {
  /// Creates a polygon bounded by [points].
  const LocationPolygon({required this.points});

  /// The points this polygon's boundary passes through, in order.
  final List<Location> points;

  /// Creates a [LocationPolygon] from the JSON object [LocationPolygon.toJson] returns.
  factory LocationPolygon.fromJson(Map<String, dynamic> json) => LocationPolygon(
    points: (json['points'] as List<dynamic>).map((point) => Location.fromJson(point as Map<String, dynamic>)).toList(),
  );

  /// The JSON object that [LocationPolygon.fromJson] reads back.
  Map<String, dynamic> toJson() => {'points': points.map((point) => point.toJson()).toList()};

  @override
  List<Object?> get props => [points];
}

/// A circle around a [center] point with a given [radius].
final class LocationCircle extends Equatable {
  /// Creates a circle around [center] with the given [radius].
  ///
  /// Asserts that [radius] is not negative.
  const LocationCircle({required this.center, required this.radius})
    : assert(radius >= 0, 'radius must not be negative.');

  /// The point at the middle of this circle.
  final Location center;

  /// The radius of this circle, in a unit the project chooses.
  ///
  /// Nothing converts it from or to the degrees of [center].
  final double radius;

  /// Creates a [LocationCircle] from the JSON object [LocationCircle.toJson] returns.
  factory LocationCircle.fromJson(Map<String, dynamic> json) => LocationCircle(
    center: Location.fromJson(json['center'] as Map<String, dynamic>),
    radius: (json['radius'] as num).toDouble(),
  );

  /// The JSON object that [LocationCircle.fromJson] reads back.
  Map<String, dynamic> toJson() => {'center': center.toJson(), 'radius': radius};

  @override
  List<Object?> get props => [center, radius];
}
