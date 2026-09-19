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

/// Reads a value back the way [Value.point], [Value.line] and the other shape factories wrote it.
extension LocationDecoding on Value {
  /// This value as a [Location], the same convention [point] wrote it
  /// under: its JSON form.
  ///
  /// Throws a [StateError] if this is not a [Varchar].
  Location get asPoint => _asJson(Location.fromJson, 'point');

  /// This value as a [LocationLine], the same convention [line] wrote it
  /// under: its JSON form.
  ///
  /// Throws a [StateError] if this is not a [Varchar].
  LocationLine get asLine => _asJson(LocationLine.fromJson, 'line');

  /// This value as a [LocationSegment], the same convention [segment] wrote
  /// it under: its JSON form.
  ///
  /// Throws a [StateError] if this is not a [Varchar].
  LocationSegment get asSegment => _asJson(LocationSegment.fromJson, 'segment');

  /// This value as a [LocationBox], the same convention [box] wrote it
  /// under: its JSON form.
  ///
  /// Throws a [StateError] if this is not a [Varchar].
  LocationBox get asBox => _asJson(LocationBox.fromJson, 'box');

  /// This value as a [LocationPath], the same convention [path] wrote it
  /// under: its JSON form.
  ///
  /// Throws a [StateError] if this is not a [Varchar].
  LocationPath get asPath => _asJson(LocationPath.fromJson, 'path');

  /// This value as a [LocationPolygon], the same convention [polygon] wrote
  /// it under: its JSON form.
  ///
  /// Throws a [StateError] if this is not a [Varchar].
  LocationPolygon get asPolygon => _asJson(LocationPolygon.fromJson, 'polygon');

  /// This value as a [LocationCircle], the same convention [circle] wrote
  /// it under: its JSON form.
  ///
  /// Throws a [StateError] if this is not a [Varchar].
  LocationCircle get asCircle => _asJson(LocationCircle.fromJson, 'circle');
}

/// A point on a map, the shape [Value.point] and [Value.asPoint]
/// read and write.
final class Location extends Equatable {
  /// A point at [lat] degrees of latitude, [lng] degrees of longitude.
  ///
  /// Asserts that both sit inside the range their own documentation gives,
  /// which also refuses a `NaN`.
  const Location({required this.lat, required this.lng})
    : assert(lat >= -90 && lat <= 90, 'lat must be -90 through 90.'),
      assert(lng >= -180 && lng <= 180, 'lng must be -180 through 180.');

  /// Degrees of latitude, from -90 at the South Pole to 90 at the North
  /// Pole.
  final double lat;

  /// Degrees of longitude, from -180 to 180, wrapping around the
  /// antimeridian.
  final double lng;

  /// Rebuilds the [Location] [toJson] wrote.
  factory Location.fromJson(Map<String, dynamic> json) =>
      Location(lat: (json['lat'] as num).toDouble(), lng: (json['lng'] as num).toDouble());

  /// This point's own fields, in the shape [Location.fromJson] rebuilds
  /// from.
  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};

  @override
  List<Object?> get props => [lat, lng];
}

/// A straight line, extending infinitely in both directions through the
/// points [a] and [b].
///
/// Stored as exactly the two points that define it — the same shape
/// [LocationSegment] stores its own endpoints in. What tells the two apart
/// is only ever which meaning a project reads into them, since neither
/// SQLite nor this package enforces one over the other.
final class LocationLine extends Equatable {
  /// The line through [a] and [b].
  const LocationLine({required this.a, required this.b});

  /// One of the two points this line passes through.
  final Location a;

  /// The other point this line passes through.
  final Location b;

  /// Rebuilds the [LocationLine] [toJson] wrote.
  factory LocationLine.fromJson(Map<String, dynamic> json) => LocationLine(
    a: Location.fromJson(json['a'] as Map<String, dynamic>),
    b: Location.fromJson(json['b'] as Map<String, dynamic>),
  );

  /// This line's own fields, in the shape [LocationLine.fromJson] rebuilds
  /// from.
  Map<String, dynamic> toJson() => {'a': a.toJson(), 'b': b.toJson()};

  @override
  List<Object?> get props => [a, b];
}

/// A straight segment, bounded by its two endpoints [a] and [b] — unlike
/// [LocationLine], it stops there rather than continuing past them.
final class LocationSegment extends Equatable {
  /// The segment from [a] to [b].
  const LocationSegment({required this.a, required this.b});

  /// One end of this segment.
  final Location a;

  /// The other end of this segment.
  final Location b;

  /// Rebuilds the [LocationSegment] [toJson] wrote.
  factory LocationSegment.fromJson(Map<String, dynamic> json) => LocationSegment(
    a: Location.fromJson(json['a'] as Map<String, dynamic>),
    b: Location.fromJson(json['b'] as Map<String, dynamic>),
  );

  /// This segment's own fields, in the shape [LocationSegment.fromJson]
  /// rebuilds from.
  Map<String, dynamic> toJson() => {'a': a.toJson(), 'b': b.toJson()};

  @override
  List<Object?> get props => [a, b];
}

/// An axis-aligned rectangle, spanning from [low] to [high].
///
/// Nothing here requires [low] to actually be the lesser corner: a project
/// that always normalises its own corners gets a predictable box back, one
/// that never does gets exactly the two points it gave.
final class LocationBox extends Equatable {
  /// The rectangle spanning [low] to [high].
  const LocationBox({required this.low, required this.high});

  /// One corner of this rectangle.
  final Location low;

  /// The opposite corner of this rectangle.
  final Location high;

  /// Rebuilds the [LocationBox] [toJson] wrote.
  factory LocationBox.fromJson(Map<String, dynamic> json) => LocationBox(
    low: Location.fromJson(json['low'] as Map<String, dynamic>),
    high: Location.fromJson(json['high'] as Map<String, dynamic>),
  );

  /// This box's own fields, in the shape [LocationBox.fromJson] rebuilds
  /// from.
  Map<String, dynamic> toJson() => {'low': low.toJson(), 'high': high.toJson()};

  @override
  List<Object?> get props => [low, high];
}

/// An ordered sequence of [points], [closed] to loop the last one back to
/// the first or left open otherwise.
final class LocationPath extends Equatable {
  /// The path through [points], [closed] or not.
  const LocationPath({required this.points, this.closed = false});

  /// The points this path passes through, in order.
  final List<Location> points;

  /// Whether this path loops its last point back to its first.
  final bool closed;

  /// Rebuilds the [LocationPath] [toJson] wrote.
  factory LocationPath.fromJson(Map<String, dynamic> json) => LocationPath(
    points: (json['points'] as List<dynamic>).map((point) => Location.fromJson(point as Map<String, dynamic>)).toList(),
    closed: json['closed'] as bool,
  );

  /// This path's own fields, in the shape [LocationPath.fromJson] rebuilds
  /// from.
  Map<String, dynamic> toJson() => {'points': points.map((point) => point.toJson()).toList(), 'closed': closed};

  @override
  List<Object?> get props => [points, closed];
}

/// A closed shape bounded by [points], its last point implicitly joined
/// back to its first.
final class LocationPolygon extends Equatable {
  /// The polygon bounded by [points].
  const LocationPolygon({required this.points});

  /// The points this polygon's boundary passes through, in order.
  final List<Location> points;

  /// Rebuilds the [LocationPolygon] [toJson] wrote.
  factory LocationPolygon.fromJson(Map<String, dynamic> json) => LocationPolygon(
    points: (json['points'] as List<dynamic>).map((point) => Location.fromJson(point as Map<String, dynamic>)).toList(),
  );

  /// This polygon's own fields, in the shape [LocationPolygon.fromJson]
  /// rebuilds from.
  Map<String, dynamic> toJson() => {'points': points.map((point) => point.toJson()).toList()};

  @override
  List<Object?> get props => [points];
}

/// A circle, centred on [center], [radius] wide in whatever unit a
/// project's own [Location] coordinates already use.
final class LocationCircle extends Equatable {
  /// The circle centred on [center], [radius] wide.
  ///
  /// Asserts that [radius] is not negative.
  const LocationCircle({required this.center, required this.radius})
    : assert(radius >= 0, 'radius must not be negative.');

  /// This circle's own centre.
  final Location center;

  /// This circle's own radius, in whatever unit [center]'s coordinates
  /// already use.
  final double radius;

  /// Rebuilds the [LocationCircle] [toJson] wrote.
  factory LocationCircle.fromJson(Map<String, dynamic> json) => LocationCircle(
    center: Location.fromJson(json['center'] as Map<String, dynamic>),
    radius: (json['radius'] as num).toDouble(),
  );

  /// This circle's own fields, in the shape [LocationCircle.fromJson]
  /// rebuilds from.
  Map<String, dynamic> toJson() => {'center': center.toJson(), 'radius': radius};

  @override
  List<Object?> get props => [center, radius];
}
