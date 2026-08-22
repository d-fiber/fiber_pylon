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

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCOPE="publish"

say() {
  echo "[$SCOPE] $1"
}

fail() {
  echo "[$SCOPE] $1" >&2
  exit 1
}

answer() {
  say "$2"
  [ -z "${GITHUB_OUTPUT:-}" ] || echo "missing=$1" >> "$GITHUB_OUTPUT"
  exit 0
}

cd "$ROOT"

package=$(awk '/^name:/ { print $2; exit }' pubspec.yaml)
version=$(awk '/^version:/ { print $2; exit }' pubspec.yaml)
tag="pub-$version"

[ -n "$package" ] || fail "pubspec.yaml has no name."
[ -n "$version" ] || fail "pubspec.yaml has no version."

if git rev-parse "$tag" >/dev/null 2>&1; then
  answer false "$tag is already on $(git rev-parse --short "$tag^{commit}"), so this version has already been sent"
fi

status=$(curl -sS -o /dev/null -w '%{http_code}' \
  "https://pub.dev/api/packages/$package/versions/$version" || echo "000")

case "$status" in
  200) answer false "pub.dev already holds $package $version, so there is nothing to send" ;;
  404) answer true  "pub.dev does not hold $package $version yet, so this push is what sends it" ;;
  *)   fail "pub.dev answered $status when asked about $package $version, and until it answers plainly nothing is sent." ;;
esac
