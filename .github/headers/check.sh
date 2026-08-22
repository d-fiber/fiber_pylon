#!/usr/bin/env bash
# Copyright (C) 2026 Fiber
#
# This Source Code Form is subject to the terms of the Mozilla Public License,
# v. 2.0. If a copy of the MPL was not distributed with this file, You can
# obtain one at https://mozilla.org/MPL/2.0/.
#
# What you may do:
# - Use this software for any purpose, including commercially, and build and
#   sell your own products on top of it.
# - Change it, and create new works based on it.
# - Distribute copies of it, with or without your changes.
# - Combine it with files under any other licence, proprietary ones included,
#   and licence that larger work on your own terms.
#
# What you must do in return:
# - Keep this notice on every file you received it on.
# - Publish, under these same terms, the source of every file covered by them
#   that you distribute, including the ones you changed, so that whoever
#   receives your version can obtain that source.
# - Leave Fiber out of it: the name "Fiber", its branding, its logos and its
#   trademarks may not be used to endorse or promote what you build, and this
#   licence grants no right to them.
#
# Disclaimer:
# AS FAR AS THE LAW ALLOWS, THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY
# OR CONDITION OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
# WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR
# NON-INFRINGEMENT. IN NO EVENT SHALL FIBER BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING BUT NOT
# LIMITED TO LOSS OF USE, DATA, PROFITS, OR BUSINESS INTERRUPTION) ARISING OUT
# OF OR RELATED TO THESE TERMS OR THE USE OR NATURE OF THE SOFTWARE, UNDER ANY
# KIND OF LEGAL CLAIM.
#
# This header is a summary written for convenience. Where it differs from the
# LICENSE file, the LICENSE file governs.


set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT"

EXTENSIONS="dart sh"
EXCLUDED=".git .dart_tool build out"
SCAN_LINES=45

COPYRIGHT="Copyright (C) 2026 Fiber"
LICENSE_NAME="Mozilla Public License"
GENERATED="auto-generated|@generated|DO NOT EDIT"

find_arguments=()
for extension in $EXTENSIONS; do
  find_arguments+=(-o -name "*.$extension")
done
unset 'find_arguments[0]'

prune_arguments=()
for directory in $EXCLUDED; do
  prune_arguments+=(-name "$directory" -o)
done

listing=$(mktemp)
trap 'rm -f "$listing"' EXIT

find . \( "${prune_arguments[@]}" -false \) -prune -o -type f \( "${find_arguments[@]}" \) -print \
  | grep -v -E '\.g\.dart$' \
  | sort > "$listing"

if [ ! -s "$listing" ]; then
  echo "No source file to check"
  exit 0
fi

missing=0
checked=0
skipped=0

while IFS= read -r file; do
  head_of_file=$(head -n "$SCAN_LINES" "$file")

  if printf '%s' "$head_of_file" | grep -qE "$GENERATED"; then
    skipped=$((skipped + 1))
    continue
  fi

  checked=$((checked + 1))

  if ! printf '%s' "$head_of_file" | grep -qF "$COPYRIGHT"; then
    echo "MISSING  $file"
    missing=$((missing + 1))
    continue
  fi

  if ! printf '%s' "$head_of_file" | grep -qF "$LICENSE_NAME"; then
    echo "STALE    $file"
    echo "         carries a copyright line but does not name the licence"
    missing=$((missing + 1))
  fi
done < "$listing"

if [ "$missing" -gt 0 ]; then
  cat >&2 <<EOF

$missing of $checked source files are missing the licence header.

Every source file carries the same header, in the comment syntax of its
language: // for Dart, # for shell. Copy it from a neighbouring file of the
same language. It goes at the very top, except in a file that starts with a
shebang, where it goes on the line after it.

The header is the notice the Mozilla Public License asks to be kept on every
file, and dropping it from a file that is distributed is what breaks the terms.
EOF
  exit 1
fi

echo ""
echo "Checked $checked source files, all carry the licence header"
echo "Skipped $skipped generated files"
