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

part of 'schema.dart';

String _foldIdentifier(String identifier) =>
    identifier.replaceAllMapped(RegExp('[A-Z]'), (match) => match[0]!.toLowerCase());

String _listOf(List<String> names) => names.join(', ');

typedef _KeyColumn = ({bool nullable, bool hasDefault, bool isGenerated});

extension _TableValidation on DeclaredTable {
  ColumnDefinition? _columnCalled(String column) {
    for (final entry in columns.entries) {
      if (_foldIdentifier(entry.key) == _foldIdentifier(column)) return entry.value;
    }
    return null;
  }

  List<String> problems() => [..._columnProblems(), ..._foreignKeyProblems()];

  List<String> _columnProblems() {
    final problems = <String>[];
    for (final MapEntry(key: column, value: definition) in columns.entries) {
      final subject = 'Table "$name", column "$column"';
      problems.addAll(_optionProblems(subject, definition));
      final reference = definition.references;
      if (reference != null) {
        problems.addAll(
          _actionProblems(
            subject,
            [_keyColumn(definition)],
            onDelete: reference.onDelete,
            onUpdate: reference.onUpdate,
          ),
        );
      }
    }
    return problems;
  }

  List<String> _optionProblems(String subject, ColumnDefinition column) => [
    if (column.defaultValue case LiteralDefault(value: Nil()) when column.notNull)
      '$subject: a NULL default on a NOT NULL column makes every insert that omits it fail.',
  ];

  _KeyColumn _keyColumn(ColumnDefinition column) =>
      (nullable: !column.notNull, hasDefault: column.defaultValue != null, isGenerated: column.generated != null);

  List<String> _foreignKeyProblems() => [
    for (final key in foreignKeys)
      ..._actionProblems(
        'Table "$name", foreign key (${_listOf(key.columns)})',
        [
          for (final column in key.columns)
            if (_columnCalled(column) case final definition?) _keyColumn(definition),
        ],
        onDelete: key.onDelete,
        onUpdate: key.onUpdate,
      ),
  ];

  List<String> _actionProblems(
    String subject,
    List<_KeyColumn> keyColumns, {
    ReferentialAction? onDelete,
    ReferentialAction? onUpdate,
  }) {
    final actions = [onDelete, onUpdate];
    final rewrites =
        onDelete == ReferentialAction.setNull ||
        onDelete == ReferentialAction.setDefault ||
        onUpdate == ReferentialAction.cascade ||
        onUpdate == ReferentialAction.setNull ||
        onUpdate == ReferentialAction.setDefault;
    return [
      if (actions.contains(ReferentialAction.setNull) && keyColumns.any((column) => !column.nullable))
        '$subject: SET NULL on a NOT NULL column fails the first time it fires. '
            'Make the column nullable or pick another action.',
      if (actions.contains(ReferentialAction.setDefault) && keyColumns.any((column) => !column.hasDefault))
        '$subject: SET DEFAULT on a column with no default sets it to NULL. '
            'Use SET NULL if that is meant, or give the column a default.',
      if (rewrites && keyColumns.any((column) => column.isGenerated))
        '$subject: a generated column cannot be rewritten, '
            'so SET NULL, SET DEFAULT and an update that cascades fail when they fire.',
    ];
  }
}

typedef _ForeignKeyUse = ({String subject, List<String> columns, String table, List<String>? referenced});

extension _CrossTableValidation on DeclaredTable {
  List<_ForeignKeyUse> get _foreignKeyUses => [
    for (final MapEntry(key: column, value: definition) in columns.entries)
      if (definition.references case final reference?)
        (
          subject: 'Table "$name", column "$column"',
          columns: [column],
          table: reference.table,
          referenced: reference.column == null ? null : [reference.column!],
        ),
    for (final key in foreignKeys)
      (
        subject: 'Table "$name", foreign key (${_listOf(key.columns)})',
        columns: key.columns,
        table: key.referencedTable,
        referenced: key.referencedColumns,
      ),
  ];

  List<String>? get _primaryKeyColumns {
    final composite = primaryKey;
    if (composite != null) return composite.columns;
    final single = columns.entries.where((entry) => entry.value.isPrimary);
    return single.length == 1 ? [single.single.key] : null;
  }

  List<Set<String>> get _uniqueKeys => [
    if (_primaryKeyColumns case final key?) key.map(_foldIdentifier).toSet(),
    for (final MapEntry(key: column, value: definition) in columns.entries)
      if (definition.unique) {_foldIdentifier(column)},
    for (final unique in uniques) unique.columns.map(_foldIdentifier).toSet(),
    for (final index in indexes)
      if (index.unique && index.where == null && index.columns.every((column) => column is NamedIndexColumn))
        index.columns.map((column) => _foldIdentifier((column as NamedIndexColumn).name)).toSet(),
  ];
}

List<String> _crossTableProblems(List<DeclaredTable> tables) {
  final byName = {for (final table in tables) _foldIdentifier(table.name): table};
  return [
    for (final table in tables)
      for (final use in table._foreignKeyUses) ..._referenceProblems(use, byName),
  ];
}

List<String> _referenceProblems(_ForeignKeyUse use, Map<String, DeclaredTable> byName) {
  final parent = byName[_foldIdentifier(use.table)];
  if (parent == null) {
    return ['${use.subject} points at table "${use.table}", which is not among the declared tables.'];
  }
  final target = use.referenced ?? parent._primaryKeyColumns;
  if (target == null) {
    return [
      '${use.subject} points at "${parent.name}" without naming columns, and "${parent.name}" has no primary key.',
    ];
  }
  final known = parent.columns.keys.map(_foldIdentifier).toSet();
  final missing = target.where((column) => !known.contains(_foldIdentifier(column)));
  if (missing.isNotEmpty) {
    return ['${use.subject} points at column "${missing.first}", which "${parent.name}" does not declare.'];
  }
  if (target.length != use.columns.length) {
    return [
      '${use.subject} has ${use.columns.length} columns but "${parent.name}" offers ${target.length} '
          'as the key it points at. SQLite fails the first write with foreign key mismatch.',
    ];
  }
  final wanted = target.map(_foldIdentifier).toSet();
  if (!parent._uniqueKeys.any((key) => key.length == wanted.length && key.containsAll(wanted))) {
    return [
      '${use.subject} points at (${_listOf(target)}) of "${parent.name}", which is neither its primary key nor '
          'unique. SQLite fails the first write with foreign key mismatch.',
    ];
  }
  return const [];
}
