# Kiln Design Summary

Kiln is a deterministic, positional, little-endian wire format with an embedded 64-byte-aligned tensor directory (`KLNT` v2). In the Mojo reference implementation (`mojo-kiln`), `reflect[T]` monomorphizes struct codecs at compile time, callers reuse a `Writer` buffer, `decode` enforces pre-allocation bounds and UTF-8 checks, and `Reader.*_fast` exposes an explicit unsafe fast path for caller-guaranteed buffers.

## Architectural Decisions

| Topic | Decision |
| --- | --- |
| **Wire format** | Kiln Version 2 normative standard ([`spec/kiln-wire-v2.md`](spec/kiln-wire-v2.md)): Frozen profile (`0`) + embedded `KLNT` v2 tensor directory (`tensors`). |
| **Excluded profiles** | Schema-evolution tags (`1`), separate offset-view wire layout (`2`), and columnar tables (`4`) remain unshipped in Version 2. See [`docs/experiments.md`](docs/experiments.md) and [`docs/comparison.md`](docs/comparison.md). |
| **Mojo API surface** | Compile-time `encode` / `decode` / `encode_framed` / `decode_framed`, `TensorDir` / `KilnTensor`, runtime `schema_from_json` + `Value`, and `gld-kilngen-mojo`. |
| **Counts & ordering** | `u32` LE counts (`u64` for tensor payload lengths), pre-allocation minimum-size guard, lexicographically sorted UTF-8 dict keys, canonical 64-byte-aligned tensor placement. |
| **Errors** | `KilnError` (`FRAME`, `SCHEMA`, `LIMIT`, `EOF`, `TYPE`, `UTF8`, `TRAILING`, `DEPTH`, plus host dynamic `RANGE`). |
| **Package** | `mojo-kiln` `0.3.0`, import `kiln`, Mojo `1.1.0`, MIT, `linux-64`. |

## GLD Benchmark Integration

`GLD.SerializerBenchmark` vendors `src/kiln` and evaluates `kiln` across the suite workloads. `Fixture.empty` avoids copying five suite lists during deserialize for Kiln alongside the CBOR, Avro, EmberJson, and BSON rows that shared that copy.
