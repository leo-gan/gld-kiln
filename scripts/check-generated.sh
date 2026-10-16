#!/usr/bin/env bash
# Regenerate into a temp directory and diff against tests/generated.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
if command -v pixi >/dev/null 2>&1; then
  MOJO=(pixi run mojo)
elif [[ -x "${HOME}/.pixi/bin/pixi" ]]; then
  MOJO=("${HOME}/.pixi/bin/pixi" run mojo)
else
  MOJO=(mojo)
fi
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
shopt -s nullglob
for schema in testdata/schema/*.json; do
  "${MOJO[@]}" run -I src src/codegen/cli.mojo -- --schema "$schema" --out "$tmp"
done
diff -ru tests/generated "$tmp"
