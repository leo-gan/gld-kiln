#!/usr/bin/env bash
# Generate Mojo structs from testdata/schema into tests/generated.
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
mkdir -p tests/generated
shopt -s nullglob
for schema in testdata/schema/*.json; do
  "${MOJO[@]}" run -I src src/codegen/cli.mojo -- --schema "$schema" --out tests/generated
done
