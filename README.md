# Kiln

Kiln is a deterministic, positional, little-endian binary wire format for typed records and dense numeric tensor directories. It is implemented from scratch across 11 languages—Mojo (reference implementation in this repository), Go, Rust, Zig, C, C++, Python, Java, Swift, C#, and TypeScript—and golden-file tested against a single normative specification.

[Serialization](https://leo-gan.github.io/serialization/) is the hub for the theory, history, and cross-language benchmarks.

## Specification Summary

| Property | Value |
| --- | --- |
| **Wire Specification** | Kiln Wire Format, Version 2 ([Published](https://leo-gan.github.io/gld-kiln/spec/) · [`spec/kiln-wire-v2.md`](spec/kiln-wire-v2.md)) |
| **Profiles** | Frozen (`0`, normative default) + embedded `KLNT` v2 tensor directory (`tensors`) |
| **Optional Framing** | 16-byte `KLN0` header with FNV-1a-64 canonical schema hash |
| **Conformance Suite** | 46 hex vectors ([`spec/kiln-v2-cases.json`](spec/kiln-v2-cases.json)) + 3 Frozen golden binaries ([`spec/golden/`](spec/golden/)) |
| **Reference Package** | `mojo-kiln` on [prefix.dev/leo-gan/leo-gan](https://prefix.dev/leo-gan/leo-gan) (`linux-64`, Mojo `1.1.0`, import `kiln`) |
| **Code Generator** | `gld-kilngen-mojo` (JSON Schema subset → Mojo structs) |
| **Documentation** | <https://leo-gan.github.io/gld-kiln/> |
| **License** | MIT |

## Core Invariants

Four architectural invariants define Kiln and distinguish it from general-purpose serializers and standalone weight formats:

1. **Schema-implied positional layout.** Record fields are encoded in declaration order with no field names, numeric tags, or inter-field padding. Both endpoints compile from the same schema; an optional `KLN0` frame seals the type with an FNV-1a-64 hash and rejects mismatches fail-closed (`SCHEMA`).
2. **Canonical representation.** Every value—and every ordered tensor directory—has a single normative byte string. Multi-byte integers and IEEE 754 floats are little-endian on all hosts, floating-point bit patterns (`-0.0`, NaN payloads) are preserved verbatim, dictionary keys are sorted lexicographically by raw UTF-8 bytes, and tensor offsets follow greedy 64-byte alignment with zero-filled gaps.
3. **Unified record and tensor buffer.** A version-2 tensor directory (`KLNT`) is a first-class Frozen value (`tensors`). A single buffer can hold structured metadata alongside 64-byte-aligned dense, low-precision (FP8, BF16, MXFP4), quantized-with-scales, or opaque foreign tensor payloads without sidecar files or double framing.
4. **Pre-allocation bounds safety.** Before allocating storage for any `list`, `dict`, string, or tensor directory, a conforming decoder verifies that `count × min_size(T)` does not overflow 64-bit arithmetic and fits within the unread buffer (`LIMIT` / `EOF`).

## Installation

Install `mojo-kiln` from [prefix.dev/leo-gan/leo-gan](https://prefix.dev/leo-gan/leo-gan):

```bash
pixi add --channel https://prefix.dev/leo-gan/leo-gan mojo-kiln
```

From a repository checkout:

```bash
pixi install
pixi run test
```

## Example

`Point` declares two 32-bit signed integers. `encode` emits their little-endian representations in declaration order (`09 00 00 00 fc ff ff ff`, 8 bytes); `decode` validates bounds and reconstructs the struct. `Writer` retains its backing allocation for reuse across calls.

```mojo
from std.collections import Span

from kiln import Writer, decode, encode


@fieldwise_init
struct Point(Copyable, Movable, Defaultable):
    var x: Int32
    var y: Int32

    def __init__(out self):
        self.x = 0
        self.y = 0


def main() raises:
    var w = Writer(64)
    encode(Point(Int32(9), Int32(-4)), w)
    var raw = w.copy_bytes()
    var back = decode[Point](Span(raw))
    print(back.x, back.y, len(raw))  # 9 -4 8
```

## Measured Baseline (Mojo 1.1.0)

Measured on an Intel Core i7-12800H (Linux, `powersave` governor, `taskset -c 2`, Mojo `1.1.0`, `experiments/decode_small.mojo`, `2026-10-16` run; hot-loop means with reused `Writer`):

| Workload | Wire Size | Encode (mean) | Decode (mean) |
| --- | ---: | ---: | ---: |
| Single 8-field `Message` | `44 B` | `15 ns` | `28 ns` (owned) |
| Batch of 100 `Message` records | `4,404 B` | `339 ns` | `1.56 µs` (owned, UTF-8 checked) |

Full methodology, `2026-10-17` post-directory re-measurements, 2 MiB tensor throughput (`74 µs`), C `-O3` ceiling, and threats to validity are documented in [Experiments](https://leo-gan.github.io/gld-kiln/experiments/).

## Documentation

- **[Overview & Comparison](https://leo-gan.github.io/gld-kiln/comparison/)** — Conceptual overview and systematic comparison against JSON, Protocol Buffers, MessagePack/CBOR, FlatBuffers/Cap'n Proto, Safetensors, GGUF, and Apache Arrow.
- **[Wire Specification (v2)](https://leo-gan.github.io/gld-kiln/spec/)** — Self-contained, language-neutral normative specification (also at [`spec/kiln-wire-v2.md`](spec/kiln-wire-v2.md)).
- **[Mojo Quickstart & Examples](https://leo-gan.github.io/gld-kiln/mojo/quickstart/)** · **[API Reference](https://leo-gan.github.io/gld-kiln/mojo/api/)** · **[Implementation & Verification](https://leo-gan.github.io/gld-kiln/mojo/internals/)** — Reference documentation for `mojo-kiln`.
- **[Experiments](https://leo-gan.github.io/gld-kiln/experiments/)** — Empirical evaluation (`E00`–`E26`) and reproduction commands.

## License

MIT. Copyright (c) 2026 Leonid Ganeline.
