# Overview and Comparison with Other Standards

This page is **non-normative**. It introduces Kiln's data model on a concrete record, then compares Kiln Version 2 systematically against established serialization and tensor interchange standards: **what Kiln changes**, **what is new**, **why each decision was made**, and **where Kiln is strictly better—or where another standard should still be used**.

For the normative wire rules, see the [Wire Specification (v2)](spec/index.md).

---

## 1. Conceptual Overview: One Record in Three Encodings

Consider a two-field struct `Point` with declaration order `x: i32`, `y: i32` and values `x = 9`, `y = -4`:

| Format | Wire Bytes (Hex / Text) | Size | Wire Overhead |
| --- | --- | ---: | --- |
| **JSON** (RFC 8259) | `{"x":9,"y":-4}` | 14 B | Field names, punctuation, decimal ASCII formatting |
| **Protocol Buffers** (`int32` fields 1 & 2)[^pb] | `08 09 10 fc ff ff ff ff ff ff ff ff 01` | 13 B | Field tags + 10-byte two's-complement varint for negative `int32` |
| **Kiln Frozen** (`spec/golden/point.kiln`) | `09 00 00 00 fc ff ff ff` | **8 B** | None (two 4-byte little-endian `i32` values in declaration order) |

[^pb]: Protocol Buffers illustration using standard `int32` (not `sint32` ZigZag, which encodes `-4` in 1 byte after its tag). Shown solely to illustrate tagged varint encoding; it is not a Kiln rule.

Variable-length values carry only their own length, never a field name. In `spec/golden/message.kiln`, the string `"hi"` encodes as `02 00 00 00 68 69` (`u32` byte length `2` + UTF-8 bytes).

Kiln composes three minimal primitives into one wire format:

1. **Frozen records (`Profile 0`):** Values in schema declaration order, fixed-width little-endian scalars, `u32` length-prefixed strings/lists/dicts, lexicographically sorted dict keys, zero inter-field padding.
2. **Optional schema seal (`KLN0` frame):** A 16-byte prefix containing a 64-bit FNV-1a hash of the canonical type tokens. A mismatched or reordered struct stops immediately with `SCHEMA` before reading field 0.
3. **Embedded tensor directory (`KLNT` v2):** A self-delimiting binary table (`64 B` header + `128 B` descriptors + optional UTF-8 name heap + `64 B`-aligned payloads) that embeds directly as a `tensors` field inside any Frozen struct.

---

## 2. Comparison Matrix

| Dimension | **Kiln v2** | **JSON** | **CBOR / MsgPack** | **Protobuf (v3)** | **FlatBuffers / Cap'n Proto** | **Safetensors** | **GGUF** | **Arrow IPC** |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Primary domain** | Shared-schema records + ML tensors | Human-readable interchange | Schema-less binary maps | Cross-version RPC | Zero-copy random-access structs | Model weight shards | Quantized LLM files | Columnar analytics |
| **Field identification** | Positional (none on wire) | String names | String/int keys + tags | Field numbers + wire types | VTable / pointer offsets | JSON header keys | Sequential KV preamble | FlatBuffers schema |
| **Scalar integers** | Fixed-width LE | Decimal text | Compact tagged | Varint (LEB128) | Fixed-width LE | Raw tensor buffers only | Fixed-width LE | Fixed-width LE |
| **Bit-exact floats (`-0.0`, NaN)** | **Yes (normative)** | No | Optional | Bit-level for `fixed`/float | Yes | Yes | Yes | Yes |
| **Unique canonical bytes** | **Yes (mandatory)** | No (RFC 8785 opt-in) | Optional (CDE) | No (not canonical) | No | No (JSON formatting) | No | No |
| **Pre-allocation count guard** | **Yes (normative)** | No | Implementation-defined | Implementation-defined | Verifier pass | Header-size cap | Implementation-defined | Buffer bounds check |
| **Structured record + tensors in 1 buffer** | **Yes (`tensors` field)** | No (base64/text) | Byte strings only | Unaligned `bytes` field | Unaligned vector / custom | No (metadata strings only) | KV header + weights | Separate record batches |
| **64-byte aligned numeric payloads** | **Yes (`KLNT` v2)** | No | No | No | Manual | No (tight packed) | Configurable (`general.alignment`) | Yes (8 B / 64 B) |
| **OCP FP8 / MXFP4 + quant links** | **Yes (closed dtypes + sibling links)** | No | No | No | No | FP8 only (no quant links) | ggml block layouts | No |
| **Opaque foreign block carriage** | **Yes (`4096..32767` + `block_size`)** | No | Tags | `bytes` | `ubyte[]` | No | Built-in ggml enum | Extension types |
| **Schema evolution (skip unknown)** | **No (fail-closed `SCHEMA`)** | Yes | Yes | **Yes** | **Yes** | N/A | Key-value extensible | Limited |
| **Columnar projection** | **No** | No | No | No | No | No | No | **Yes** |

---

## 3. What Kiln Changes (and Why)

### 3.1 Removing Field Names, Tags, and Offset Tables
- **Prior standards:** JSON, MessagePack, and CBOR write field names (or integer keys) on every record; Protobuf writes a tag byte/varint per field; FlatBuffers writes a vtable and per-field offsets.
- **What Kiln changes:** Fields are emitted strictly in schema declaration order with zero metadata and zero inter-field padding.
- **Why:** When both processes compile from the same schema (co-deployed services, training/inference pipelines, local IPC, cache snapshots), wire tags repeat information the compiler already statically resolved. On a batch of `N` records, every tag dispatch branch and key lookup multiplies by `N × fields`.

### 3.2 Fixed-Width Little-Endian Scalars Instead of Varints
- **Prior standards:** Protobuf, CBOR, and MessagePack encode integers with variable-length representations to save bytes on small non-negative values.
- **What Kiln changes:** All integers and floats use fixed widths in mandatory little-endian order on all hosts, preserving every floating-point bit (`-0.0`, NaN payloads).
- **Why:** On little-endian CPUs (x86-64, AArch64), fixed-width scalars compile to single unaligned loads/stores with zero branches. Experiment [E04](experiments.md) and prior cross-language benchmarks (`dagr-frozen` vs `dagr-frozen-packed`, Zig `comptime-bin`) show varints trade decode CPU cycles and branch mispredictions for modest size savings—and degrade sharply on negative `int32` values without ZigZag.

### 3.3 Binary Fixed-Width Tensor Directory Instead of Text/KV Headers
- **Prior standards:** Safetensors stores tensor shapes and offsets in a JSON header; GGUF stores metadata in a variable-length sequential key-value preamble.
- **What Kiln changes:** `KLNT` v2 uses a fixed 64-byte header and fixed 128-byte descriptors, plus a single gapless UTF-8 name heap, followed by 64-byte-aligned payloads.
- **Why:** Eliminating a JSON parser from the tensor loader enables constant-time arithmetic validation (`directory_bytes == tensor_count × 128 + name_bytes`) before touching descriptors or allocating memory. The entire directory can be bounds-checked in a single linear pass and returned as zero-copy views.

### 3.4 Fail-Closed Schema Fingerprinting Instead of Silent Coercion
- **Prior standards:** Untagged binary dumps silently misinterpret swapped or added fields; tagged formats silently ignore unknown fields.
- **What Kiln changes:** An optional 16-byte `KLN0` frame carries an FNV-1a-64 hash over the canonical type token grammar. Any field addition, removal, rename, type change, or reorder changes the hash and fails immediately with `SCHEMA` before decoding byte 16.
- **Why:** Silent misinterpretation is catastrophic for positional formats, and manual version integers drift when developers reorder fields without bumping the version. A deterministic type hash makes schema agreement machine-checked across all 11 languages.

### 3.5 Normative Pre-Allocation Bounds Guard
- **Prior standards:** Many binary codecs either allocate containers from raw wire counts (enabling allocation-amplification DoS from tiny buffers) or leave defense behavior implementation-defined.
- **What Kiln changes:** Every counted container (`list`, `dict`, `str`, `KLNT` directory) MUST verify `count ≤ cap`, no `u64` multiplication overflow (`LIMIT`), and `count × min_size(T) ≤ remaining_bytes` (`EOF`) **before** allocating element storage.
- **Why:** Untrusted or truncated buffers fail deterministically in O(1) time and O(1) memory, and every conforming language port produces the exact same error code on hostile inputs.

---

## 4. What Is New in Kiln

No single technique in Kiln is exotic on its own; what is new is **combining record serialization and ML tensor interchange under one strict, minimal, canonical wire specification**:

1. **Records and multi-tensor directories in one self-delimiting buffer.** Unlike Safetensors or GGUF (which are top-level model weight files) and unlike Protobuf/JSON (which treat tensors as opaque unaligned blobs or text), Kiln makes `tensors` a first-class Frozen struct field. An inference request `(request_id, prompt, temperature, [input_ids, attention_mask, kv_cache])` or a training sample serializes as one contiguous buffer with zero sidecar files and zero double framing.
2. **First-class low-precision ML dtypes with non-destructive quantization links.** The closed 19-dtype table natively covers `f16`, `bf16`, OCP OFP8 (`f8e4m3`, `f8e5m2`), packed 4-bit integers (`i4`, `u4`), and OCP Microscaling (`e2m1`, `e8m0`). Quantization schemes `1` and `2` link data tensors to sibling block-scale and outer-scale tensors, verifying exact group counts (`⌈shape[a] / g⌉ × ∏_{i≠a} shape[i]`) structurally while prohibiting decoder-side dequantization or rounding.
3. **Bounded opaque foreign blocks (`4096..32767`).** Rather than rejecting vendor block formats or bloating the specification into a catalog of external quantization schemes (such as ggml's `Q4_K`), Kiln transports them inside the same descriptor table with a mandatory UTF-8 layout identifier and `block_size` divisibility check.
4. **Canonical-only encoding paired with a deterministic 12-step validation order.** Both Frozen values and `KLNT` v2 directories admit exactly one valid byte representation per logical value, and multi-fault invalid inputs map to one unique expected error code across all 11 independent implementations, enforced by 46 self-checking conformance vectors.

---

## 5. Why (and When) Kiln Is Better — and When to Choose Another Standard

### Where Kiln Is Strictly Better

| Workload | Why Kiln Outperforms Alternatives |
| --- | --- |
| **Co-deployed RPC / IPC & batch record pipelines** | Zero field tags, zero varint branches, compile-time struct specialization, and single-reserve buffer reuse yield ~15 ns encode / ~28 ns decode for a 44-byte record and ~3.4 ns/record encode in a 100-record batch (Mojo 1.1.0; see [Experiments](experiments.md)). |
| **ML inference requests & training samples (metadata + tensors)** | Replaces ad-hoc `JSON/Protobuf + Safetensors/sidecar` two-format pipelines with a single 64-byte-aligned, zero-copy-capable, pre-allocation-safe buffer. |
| **Bit-exact numerical caching & cross-language testing** | Mandatory little-endian, NaN/`-0.0` preservation, sorted dict keys, and greedy canonical tensor placement ensure byte-for-byte identity across 11 languages—enabling direct byte hashing, deduplication, and golden-file testing. |
| **Untrusted binary ingestion of dense data** | Fixed-width descriptor arithmetic + deterministic check order + pre-allocation minimum-size guard prevent hostile count allocations without requiring an external verifier schema pass. |

### When Another Standard Is the Right Choice

Kiln intentionally refuses features that conflict with its four invariants:

| Requirement | Recommended Standard | Why Kiln Declines It |
| --- | --- | --- |
| **Human inspection & ad-hoc text editing** | **JSON** (RFC 8259) | Kiln omits field names and stores binary machine bits. |
| **Independent forward/backward schema evolution** | **Protocol Buffers** / **FlatBuffers** | Skipping unknown fields requires per-field tags or vtables, which add the per-field bytes and branches Frozen removes. |
| **Analytical column projection across large tables** | **Apache Arrow IPC** / **Parquet** | Projecting one field across `N` rows requires a columnar (SoA) layout; Kiln stores record batches row-wise (AoS). |
| **Storage/network size reduction on compressible data** | **Kiln + external LZ4 / Zstandard** | Wire-level compression breaks zero-copy payload views and hurts latency on small messages ([E14](experiments.md)). |
| **In-place random access into deeply nested variable structs** | **FlatBuffers** / **Cap'n Proto** | Requires per-field relative pointers/offsets inside records; Kiln only aligns tensor payloads inside `KLNT`. |
