#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/package-snapshot-charts.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL: %s\nexpected:\n%s\nactual:\n%s\n' "$label" "$expected" "$actual" >&2
    exit 1
  fi
}

git -C "$tmp_dir" init -q
git -C "$tmp_dir" config user.name "test"
git -C "$tmp_dir" config user.email "test@example.com"

printf 'one\n' > "$tmp_dir/file.txt"
git -C "$tmp_dir" add file.txt
git -C "$tmp_dir" commit -q -m one
first="$(git -C "$tmp_dir" rev-parse HEAD)"

printf 'two\n' > "$tmp_dir/file.txt"
git -C "$tmp_dir" commit -q -am two
second="$(git -C "$tmp_dir" rev-parse HEAD)"

printf 'three\n' > "$tmp_dir/file.txt"
git -C "$tmp_dir" commit -q -am three
third="$(git -C "$tmp_dir" rev-parse HEAD)"

actual="$(
  cd "$tmp_dir"
  GITHUB_EVENT_BEFORE="$first" GITHUB_SHA="$third" \
    bash "$script" --print-commits
)"
assert_eq "$(printf '%s\n%s' "$second" "$third")" "$actual" "push range includes every commit after before"

zero_sha="0000000000000000000000000000000000000000"
actual="$(
  cd "$tmp_dir"
  GITHUB_EVENT_BEFORE="$zero_sha" GITHUB_SHA="$third" \
    bash "$script" --print-commits
)"
assert_eq "$third" "$actual" "new branch or missing before falls back to head commit"

actual="$(
  cd "$tmp_dir"
  SNAPSHOT_COMMITS="$first $third" \
    bash "$script" --print-commits
)"
assert_eq "$(printf '%s\n%s' "$first" "$third")" "$actual" "explicit snapshot commit override is honored"
