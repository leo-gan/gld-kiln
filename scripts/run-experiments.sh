#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
taskset -c 2 pixi run mojo run -I src experiments/variants.mojo
gcc -O3 -o /tmp/kiln-message-e15 experiments/E15-c-ceiling/kiln_message.c
taskset -c 2 /tmp/kiln-message-e15
