#!/usr/bin/env bash
# Precompile the published package into /tmp/mojo-kiln-pkg.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
out="${MOJO_KILN_PKG:-/tmp/mojo-kiln-pkg}"
mkdir -p "$out"
if command -v pixi >/dev/null 2>&1; then
  MOJO=(pixi run mojo)
elif [[ -x "${HOME}/.pixi/bin/pixi" ]]; then
  MOJO=("${HOME}/.pixi/bin/pixi" run mojo)
else
  MOJO=(mojo)
fi
"${MOJO[@]}" precompile -I src src/kiln -o "$out/kiln.mojoc"
"${MOJO[@]}" build -I src src/codegen/cli.mojo -o "$out/gld-kilngen-mojo"
echo "wrote $out"
