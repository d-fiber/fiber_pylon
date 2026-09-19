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

part of 'database.dart';

/// Where a statement runs: straight on [AppStorage], or inside one of its
/// transactions.
abstract interface class _Executor {
  Future<void> execute(String sql, [List<DatabaseType> arguments = const []]);

  Future<List<DatabaseRow>> rawQuery(String sql, [List<DatabaseType> arguments = const []]);
}

final class _StorageExecutor implements _Executor {
  const _StorageExecutor();

  @override
  Future<void> execute(String sql, [List<DatabaseType> arguments = const []]) => AppStorage.database.execute(sql, arguments);

  @override
  Future<List<DatabaseRow>> rawQuery(String sql, [List<DatabaseType> arguments = const []]) =>
      AppStorage.database.rawQuery(sql, arguments);
}

final class _TransactionExecutor implements _Executor {
  const _TransactionExecutor(this._txn);

  final DatabaseTransaction _txn;

  @override
  Future<void> execute(String sql, [List<DatabaseType> arguments = const []]) => _txn.execute(sql, arguments);

  @override
  Future<List<DatabaseRow>> rawQuery(String sql, [List<DatabaseType> arguments = const []]) =>
      _txn.rawQuery(sql, arguments);
}

/// Runs [action] in one transaction on [AppStorage].
Future<R> _atomically<R>(Future<R> Function(_Executor executor) action) =>
    AppStorage.database.transaction((txn) => action(_TransactionExecutor(txn)));

/// A SQL fragment and the values its `?` placeholders stand for, in order.
typedef _Compiled = ({String sql, List<DatabaseType> args});

final _fieldName = RegExp(r'^[A-Za-z0-9_-]+$');
final _collectionName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

bool _isDocumentId(Object field) => field is Field && field._isDocumentId;

/// The names [field] walks through, outermost first.
///
/// Every name is checked against `[A-Za-z0-9_-]+`: a field name is written
/// into the SQL itself, not bound as a value — an index is only used when the
/// path it was built on appears as a literal — so nothing outside that set
/// may ever reach it.
List<String> _segmentsOf(Object field) {
  final List<String> segments;
  if (field is String) {
    segments = field.split('.');
  } else if (field is FieldReference && !_isDocumentId(field)) {
    segments = field.name.split('.');
  } else {
    throw ArgumentError.value(field, 'field', 'must be a Field or a ListField of the data, not the document id');
  }
  for (final segment in segments) {
    if (!_fieldName.hasMatch(segment)) {
      throw ArgumentError.value(field, 'field', 'must be dot-separated names made of letters, digits, "_" or "-"');
    }
  }
  return segments;
}

/// The JSON path [field] names, as a SQL string literal.
String _jsonPathLiteral(Object field) {
  if (_isDocumentId(field)) {
    throw ArgumentError.value(field, 'field', 'the document id is not a field of its data');
  }
  return "'\$.${_segmentsOf(field).map((segment) => '"$segment"').join('.')}'";
}

/// The SQL expression that reads [field] out of a row.
String _fieldExpression(Object field) => _isDocumentId(field) ? 'id' : 'json_extract(data, ${_jsonPathLiteral(field)})';

/// [value] as something SQLite can compare against what [_fieldExpression]
/// reads back: a [bool] as `1` or `0`, a [DateTime] as its UTC ISO-8601 text,
/// an [Enum] as its name.
DatabaseType _operand(Object? value) => switch (value) {
  null => throw ArgumentError.notNull('value'),
  bool flag => DatabaseType.boolean(flag),
  int whole => DatabaseType.integer(whole),
  double real => DatabaseType.real(real),
  String text => DatabaseType.varchar(text),
  DateTime time => DatabaseType.varchar(time.toUtc().toIso8601String()),
  Enum member => DatabaseType.varchar(member.name),
  _ => throw ArgumentError.value(value, 'value', 'cannot be compared: only bool, num, String, DateTime and Enum can'),
};

String _placeholders(int count) => List.filled(count, '?').join(', ');

num? _number(DatabaseType? value) => switch (value) {
  Integer(:final value) => value,
  Real(:final value) => value,
  _ => null,
};

/// [text] with the characters `LIKE` reads as a pattern made literal, for
/// use with `ESCAPE '\'`.
String _escapeLike(String text) => text.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
