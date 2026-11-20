# Implementation Architecture and Verification

This page summarizes the compile-time code generation techniques, memory-access fast paths, and verification suite in `mojo-kiln`.

---

## 1. Implementation Techniques

### Compile-Time Field Reflection
Struct serialization and deserialization are monomorphized at compile time via `reflect[T].field_count()`, `field_types()`, `field_names()`, and `field_ref[idx]`. No runtime type descriptors, reflection tables, or virtual dispatch remain in compiled code.

### Leaf-Struct Single-Reserve Fast Path
Structs whose fields are exclusively scalars and `String` values (up to 16 fields, unrolled in `_fields_poke` in `src/kiln/codec.mojo`) take a specialized encode path ([E21](../experiments.md)):

1. Compute the exact encoded byte size once (`_size_struct`).
2. Verify `need ≤ w.max_bytes` and call `w.ensure(need)` once.
3. Write every scalar and string through a single base pointer without per-field capacity checks.

Structs containing nested structs, `List`, `Optional`, `Dict`, or `TensorDir` retain per-field capacity checks so a nested container cannot write past its reservation. Once `Writer` reaches steady-state capacity, subsequent encodes perform zero heap allocations.

### Unaligned Little-Endian Loads/Stores and Bulk POD Copies
- On little-endian hosts (`is_little_endian()`), 2-, 4-, and 8-byte scalars compile to single unaligned `Pointer.unsafe_store[alignment=1]` / `unsafe_load[alignment=1]` operations ([E22](../experiments.md)). Portable byte-shift fallbacks remain in source for big-endian targets.
- `List[T]` for fixed-width numeric `T` (`Int8`..`Int64`, `UInt8`..`UInt64`, `Int`, `UInt`, `Float32`, `Float64`) and `f64_directory` emit and load payloads via single `unsafe_memcpy` calls, guarded at compile time by `is_little_endian()` so multi-byte bulk copies cannot silently emit big-endian bytes ([E07](../experiments.md)).

### Fast String Decode and SWAR ASCII Validation
- `Reader.read_string` validates bounds first, then copies bytes directly into `String(unsafe_uninit_length=n)` with `unsafe_memcpy`, avoiding intermediate span slicing ([E23](../experiments.md)).
- UTF-8 validation (`src/kiln/utf8.mojo`) performs an 8-byte unaligned OR-reduction scan on little-endian hosts: pure ASCII strings (no high bit `0x80` set in any byte) pass without entering the multi-byte UTF-8 state machine ([E24](../experiments.md)).

### Canonical Dictionary Ordering and Custom Codecs
- `Dict[String, V]` keys are sorted lexicographically by raw UTF-8 bytes before emission so iteration order never leaks onto the wire.
- Custom user types can conform to `KilnCodec` (and `KilnMin`) to replace derived reflection while keeping stdlib containers conformant to the specification.

---

## 2. Verification Suite and Regeneration

Run all Mojo tests with `pixi run test`.

| Path | Coverage |
| --- | --- |
| `tests/test_roundtrip.mojo` | All scalars, nested structs, lists, dicts, `KLN0` frames, and nesting depth limits. |
| `tests/test_golden.mojo` | Byte-for-byte match against `spec/golden/point.kiln`, `message.kiln`, and `message.frame.kiln` produced by the independent Python reference codec (`spec/reference/kiln_ref.py`). |
| `tests/test_malformed.mojo` | Truncation (`EOF`), invalid bool (`TYPE`), oversized length (`LIMIT`/`EOF`), invalid UTF-8 (`UTF8`), trailing bytes (`TRAILING`), invalid frame (`FRAME`), hostile list counts, and `read_string_slice` views. |
| `tests/test_fuzz.mojo` | Randomized message round-trips (50 cases) and random truncated prefixes verifying error returns without crashes. |
| `tests/test_value.mojo` | Byte-for-byte equivalence between runtime `schema_from_json` + `Value` encoding and compile-time struct reflection. |
| `tests/test_gen.mojo` | Round-trip verification of `gld-kilngen-mojo` outputs for `testdata/schema/point.json` and `message.json`. |
| `tests/test_tensor.mojo` | `f64_directory` round-trip and exact IEEE 754 bit patterns. |
| `tests/test_tensor_v2.mojo` | Full `KLNT` v2 conformance: all 46 cases in `spec/kiln-v2-cases.json`, struct embedding, pre-allocation bounds, byte order, quantization, opaque layouts, and check order. |
| `testdata/schema/` | JSON Schema fixtures consumed by `gld-kilngen-mojo`. |

### Maintenance Commands

| Task | Command |
| --- | --- |
| Run full Mojo test suite | `pixi run test` |
| Regenerate Frozen golden binaries | `python3 spec/reference/gen_golden.py` (or `pixi run golden`) |
| Regenerate & self-check v2 conformance vectors | `python3 spec/reference/gen_v2_cases.py` |
| Regenerate Mojo structs from `testdata/schema/` | `pixi run generate` |
| Diff generated structs against `tests/generated/` | `pixi run check-generated` |
