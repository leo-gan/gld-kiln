# Kiln

Kiln is a deterministic, positional, little-endian binary wire format for typed records and dense numeric tensor directories. It is implemented from scratch across 11 languages—Mojo (reference implementation in this repository), Go, Rust, Zig, C, C++, Python, Java, Swift, C#, and TypeScript—and golden-file tested against a single normative specification.

## Specification Summary

| Property | Value |
| --- | --- |
| **Wire Specification** | Kiln Wire Format, Version 2 ([Read specification](spec/index.md)) |
| **Profiles** | Frozen (`0`, normative default) + embedded `KLNT` v2 tensor directory (`tensors`) |
| **Optional Framing** | 16-byte `KLN0` header with FNV-1a-64 canonical schema hash |
| **Conformance Suite** | 46 hex vectors (`spec/kiln-v2-cases.json`) + 3 Frozen golden binaries (`spec/golden/`) |
| **Reference Package** | `mojo-kiln` on [prefix.dev/leo-gan/leo-gan](https://prefix.dev/leo-gan/leo-gan) (`linux-64`, Mojo `1.1.0`, import `kiln`) |
| **Code Generator** | `gld-kilngen-mojo` (JSON Schema subset → Mojo structs) |
| **License** | MIT |

## Core Invariants

Four architectural invariants define Kiln and distinguish it from general-purpose serializers and standalone weight formats:

1. **Schema-implied positional layout.** Record fields are encoded in declaration order with no field names, numeric tags, or inter-field padding. Both endpoints compile from the same schema; an optional `KLN0` frame seals the type with an FNV-1a-64 hash and rejects mismatches fail-closed (`SCHEMA`).
2. **Canonical representation.** Every value—and every ordered tensor directory—has a single normative byte string. Multi-byte integers and IEEE 754 floats are little-endian on all hosts, floating-point bit patterns (`-0.0`, NaN payloads) are preserved verbatim, dictionary keys are sorted lexicographically by raw UTF-8 bytes, and tensor offsets follow greedy 64-byte alignment with zero-filled gaps.
3. **Unified record and tensor buffer.** A version-2 tensor directory (`KLNT`) is a first-class Frozen value (`tensors`). A single buffer can hold structured metadata alongside 64-byte-aligned dense, low-precision (FP8, BF16, MXFP4), quantized-with-scales, or opaque foreign tensor payloads without sidecar files or double framing.
4. **Pre-allocation bounds safety.** Before allocating storage for any `list`, `dict`, string, or tensor directory, a conforming decoder verifies that `count × min_size(T)` does not overflow 64-bit arithmetic and fits within the unread buffer (`LIMIT` / `EOF`).

## Documentation Map

- **[Overview & Comparison](comparison.md)** — Non-normative conceptual overview and a systematic comparison against JSON, Protocol Buffers, MessagePack/CBOR, FlatBuffers/Cap'n Proto, Safetensors, GGUF, and Apache Arrow: what Kiln changes, what is new, why, and when Kiln is preferable.
- **[Wire Specification (v2)](spec/index.md)** — Self-contained, language-neutral normative standard (byte layouts, BNF schema-hash grammar, dtypes, quantization invariants, 12-step deterministic check order, error taxonomy, JSON Schema subset, and all 46 conformance vectors).
- **[Mojo Implementation](mojo/quickstart.md)** — Installation, runnable examples, complete [API Reference](mojo/api.md), and [Implementation & Verification](mojo/internals.md) notes for `mojo-kiln`.
- **[Experiments](experiments.md)** — Hardware-pinned empirical evaluation (E00–E26) justifying every wire and implementation decision, including threats to validity and reproduction commands.

## Measured Baseline (Mojo 1.1.0)

On an Intel i7-12800H (Linux, `powersave` governor, pinned core `taskset -c 2`, Mojo 1.1.0, `experiments/decode_small.mojo`), the 44-byte eight-field benchmark record encodes in mean **15 ns** and decodes into owned strings in mean **28 ns**; a batch of 100 records (4,404 bytes) encodes in mean **339 ns** and decodes with UTF-8 validation in mean **1.56 µs** (2026-10-16 run; see [Experiments](experiments.md) for the 2026-10-17 post-directory re-measurement, 2 MiB tensor throughput, C `-O3` ceiling, and methodology).
