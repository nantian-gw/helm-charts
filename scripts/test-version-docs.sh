#!/usr/bin/env bash
set -euo pipefail

docs=(README.md charts/nantian-gw/VALUES.md)
combined="$(mktemp)"
trap 'rm -f "$combined"' EXIT

cat "${docs[@]}" >"$combined"

if ! grep -F 'https://chart.nantian.dev' "$combined" >/dev/null; then
  echo "chart docs must mention https://chart.nantian.dev" >&2
  exit 1
fi

if grep -F 'https://charts.nantian.dev' "$combined" >/dev/null; then
  echo "chart docs must use https://chart.nantian.dev" >&2
  exit 1
fi

if grep -E 'default `?tag`? is an immutable `?sha-|默认 `?tag`? 是.*不可变 `?sha-' "$combined" >/dev/null; then
  echo "chart docs still claim the default image tag is sha-pinned" >&2
  exit 1
fi

if ! grep -Ei 'default.*latest|默认.*latest' "$combined" >/dev/null; then
  echo "chart docs must describe the current latest image tag default" >&2
  exit 1
fi
