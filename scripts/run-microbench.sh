#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
exec taskset -c 2 pixi run mojo run -I src experiments/variants.mojo
