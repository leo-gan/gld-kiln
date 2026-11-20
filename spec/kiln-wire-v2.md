# Kiln Wire Format Specification — Version 2

| Field | Value |
| --- | --- |
| **Standard** | Kiln Wire Format, Version 2 |
| **Status** | Normative Specification |
| **Canonical URL** | `https://leo-gan.github.io/gld-kiln/spec/` |
| **Conformance Suite** | `spec/kiln-v2-cases.json` (46 vectors), `spec/golden/` |
| **Reference Codec** | `spec/reference/kiln_ref.py` (Frozen), `spec/reference/gen_v2_cases.py` (Directory v2) |
| **Author** | Leonid Ganeline |

## Abstract

Kiln is a deterministic, positional, little-endian binary wire format for typed records and dense numeric tensor directories. It is designed for systems in which producer and consumer share a compiled schema: record fields are encoded in declaration order without field names, numeric tags, or inter-field padding. An optional 16-byte frame (`KLN0`) seals a value with a 64-bit FNV-1a fingerprint of its canonical type description, failing closed on schema mismatch. A version-2 tensor directory (`KLNT`) is a first-class record value that stores zero or more multi-dimensional numeric arrays—including IEEE floating-point, OCP FP8/MXFP4, packed 4-bit integers, sibling quantization scale links, and opaque vendor layouts—behind a fixed-width binary descriptor table with 64-byte payload alignment.

---

## 1. Scope and Conformance {#scope}

This specification defines the normative binary representation, canonical encoding rules, pre-allocation bounds checks, deterministic validation order, error codes, schema fingerprint grammar, and portable JSON Schema type mapping for Kiln Version 2. It does not specify host language APIs, transport framing, or storage containers.

### 1.1 Normative Language {#conformance}

The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this document are to be interpreted as described in BCP 14 [\[RFC2119\]](#references) [\[RFC8174\]](#references) when, and only when, they appear in all capitals, as shown here.

### 1.2 Terminology {#terminology}

| Term | Definition |
| --- | --- |
| **Wire** | The sequence of bytes produced by an encoder and consumed by a decoder (in memory, over a transport, or in a file). |
| **Schema** | The static description of a value's types, field names, and struct field declaration order. Not transmitted on the wire. |
| **Positional encoding** | Encoding values in schema-fixed order without per-field names, numeric tags, or offset tables. |
| **Frozen** | Kiln's default record encoding (profile code `0`): declaration order, fixed-width little-endian scalars, zero inter-field padding, sorted dictionary keys. |
| **Frame** | Optional 16-byte prefix (`KLN0`) preceding a single Frozen value and carrying its 64-bit schema hash. |
| **Tensor directory** | A version-2 `KLNT` block holding zero or more tensors behind a 64-byte header, 128-byte descriptors, an optional name heap, and 64-byte-aligned payloads. Canonical type name: `tensors`. |
| **Descriptor** | The 128-byte fixed-width metadata record describing one tensor in a `KLNT` directory. |
| **Payload** | The contiguous byte region holding a single tensor's raw element bits, aligned to a 64-byte offset from the start of its directory. |
| **Canonical layout** | The unique byte sequence an encoder MUST emit and a decoder MUST require for a given value or ordered tensor list. |
| **Cap** | An implementation-configured limit at or below the wire maximum (`2³² − 1` for `u32` counts; `2⁶⁴ − 1` for `u64` byte lengths). Exceeding the cap raises `LIMIT`. |
| **View** | A zero-copy read that borrows bytes directly from the caller's input buffer without allocating payload storage. |
| **Owned copy** | A read that copies decoded data into newly allocated storage owned by the returned value, allocated only after bounds validation succeeds. |

### 1.3 Conformance Classes {#conformance-classes}

- **Conforming Encoder:** Emits only canonical bytes satisfying every **MUST** / **MUST NOT** requirement of §§2–6.
- **Conforming Decoder:** Accepts every valid canonical input within its configured caps, rejects every invalid input with the exact error code dictated by §§2–7, and never allocates storage proportional to an unvalidated count.
- **Trusted-Decoder Mode:** An explicit, opt-in non-default mode permitted to skip specific checks on caller-guaranteed inputs (§7.3).

### 1.4 Excluded Scope {#not-in-this-version}

The following mechanisms are intentionally excluded from Version 2:

1. **Per-field schema evolution tags** (e.g., skipping unknown fields). Schema mismatches are rejected fail-closed via the `KLN0` frame hash.
2. **Columnar record layouts** (reserved profile code `4`). A homogeneous `list<T>` of fixed-width numbers is already contiguous.
3. **Wire-level compression.** Compression is applied externally to complete encoded buffers if desired.
4. **Decoder-side dequantization or widening.** Quantization links are validated structurally; element bits remain unmodified.
5. **Device pointers or external memory handles.** A Kiln buffer is a self-contained sequence of bytes.
6. **Tensor directory versions other than 2.** There is no normative version-1 directory layout; any `KLNT` version byte other than `2` **MUST** be rejected with `FRAME`.

---

## 2. Byte Order and Numeric Representation {#byte-order}

1. **Little-endian mandate.** Every multi-byte integer and multi-byte floating-point value in Frozen records, `KLN0` frames, `KLNT` headers, `KLNT` descriptors, and tensor payloads **MUST** be encoded in little-endian byte order on all host architectures.
2. **Host copy rule.** Direct copying between host memory and the wire buffer is conforming **if and only if** the host is little-endian and the host type has identical width and bit representation to the wire type. On a big-endian host, a conforming implementation **MUST** either byte-swap every multi-byte scalar or refuse the operation before writing. Emitting native big-endian bytes as Kiln is non-conforming.
3. **Bit-exact floating-point preservation.** Encoders and decoders **MUST** preserve exact IEEE 754 bit patterns [\[IEEE754\]](#references), including signed zero and NaN payloads:
   - `f32(1.0)` = `00 00 80 3f` (`0x3F800000`)
   - `f32(-0.0)` = `00 00 00 80` (`0x80000000`, case `kiln-v2-f32-negzero`)
   - `f64` quiet NaN payload `1` = `01 00 00 00 00 00 f8 7f` (`0x7FF8000000000001`, case `kiln-v2-f64-nan`)
   - `f16(1.0)` = `00 3c` (`0x3C00`, case `kiln-v2-f16-named`)
   - `bf16(1.0)` = `80 3f` (`0x3F80`, case `kiln-v2-bf16`)
4. **Single-byte and packed sub-byte payloads.** Single-byte dtypes and packed 4-bit nibble streams (`i4`, `u4`, `e2m1`) have no multi-byte endianness and **MAY** be copied directly on any host. Within each byte of a packed stream, element `2k` occupies the low nibble (bits `0..3`) and element `2k + 1` occupies the high nibble (bits `4..7`). For an odd element count `n`, bits `4..7` of the final byte **MUST** be `0`; a nonzero trailing high nibble **MUST** be rejected with `TYPE` (case `kiln-v2-high-nibble`).
5. **Directory endianness flag.** A `KLNT` v2 header **MUST** set flag bit `1` (`0x02`). A decoder **MUST** reject a directory whose bit `1` is clear with `FRAME` (case `kiln-v2-le-clear`). This bit certifies adherence to this section; it does not select an alternate byte order.

---

## 3. Frozen Profile Encoding (Profile 0) {#frozen-values}

Frozen is the default value encoding. Struct fields are written contiguously in schema declaration order with **no field names, no tags, and no inter-field padding**.

### 3.1 Primitive and Container Wire Layouts

| Canonical Type | Width / Prefix | Wire Encoding & Validation Rules |
| --- | --- | --- |
| `bool` | 1 byte | `0x00` = false, `0x01` = true. Any byte `≥ 0x02` **MUST** raise `TYPE`. |
| `i8` | 1 byte | Signed 8-bit two's complement integer. |
| `i16` | 2 bytes | Signed 16-bit two's complement integer, little-endian. |
| `i32` | 4 bytes | Signed 32-bit two's complement integer, little-endian. |
| `i64` | 8 bytes | Signed 64-bit two's complement integer, little-endian. |
| `int` | 8 bytes | Signed 64-bit two's complement integer, little-endian. Wire width is fixed at 8 bytes regardless of host pointer size; hashed distinctly from `i64` (§5.3). |
| `u8` | 1 byte | Unsigned 8-bit integer. |
| `u16` | 2 bytes | Unsigned 16-bit integer, little-endian. |
| `u32` | 4 bytes | Unsigned 32-bit integer, little-endian. |
| `u64` | 8 bytes | Unsigned 64-bit integer, little-endian. |
| `uint` | 8 bytes | Unsigned 64-bit integer, little-endian. Wire width is fixed at 8 bytes regardless of host pointer size; hashed distinctly from `u64` (§5.3). |
| `f32` | 4 bytes | IEEE 754 binary32, little-endian, bit-preserving. |
| `f64` | 8 bytes | IEEE 754 binary64, little-endian, bit-preserving. |
| `str` | `u32` + `n` bytes | `u32` LE byte length `n`, followed by `n` UTF-8 bytes [\[RFC3629\]](#references) with no NUL terminator. Invalid UTF-8 **MUST** raise `UTF8`. |
| `list<u8>` / `bytes` | `u32` + `n` bytes | `u32` LE byte count `n`, followed by `n` raw bytes. Identical wire layout. |
| `list<T>` | `u32` + elements | `u32` LE element count `n`, followed by `n` encoded `T` values in index order. For fixed-width numeric `T`, the payload is `n × width(T)` contiguous little-endian bytes. |
| `opt<T>` | 1 byte `[+ T]` | Presence tag byte: `0x00` = absent (no following bytes); `0x01` = present, immediately followed by encoded `T`. Any tag `≥ 0x02` **MUST** raise `TYPE`. |
| `dict<str,V>` | `u32` + entries | `u32` LE entry count `n`, followed by `n` consecutive `(key: str, value: V)` pairs. Encoders **MUST** emit keys in strictly ascending lexicographic order of raw unsigned UTF-8 bytes (implying unique keys). Decoders **MUST** reject out-of-order or duplicate keys with `TYPE`. |
| `struct` | Sum of fields | Concatenation of field encodings in schema declaration order, with zero padding between fields. |
| `tensors` | `KLNT` v2 block | One complete canonical version-2 tensor directory (§6), starting with magic `KLNT`. The directory header determines `block_end`; the next struct field starts immediately at `block_end` with no padding. |

### 3.2 Standalone Decoding and Nesting Depth

1. **Exact buffer consumption.** Decoding a standalone Frozen value (unframed or framed) **MUST** consume the entire input buffer. If unread bytes remain after the root value completes, the decoder **MUST** raise `TRAILING`.
2. **Nesting depth limit.** Each container entry (`struct`, `list<T>`, `opt<T>`, `dict<str,V>`, `tensors`) increments nesting depth by 1. Encoders and decoders **MUST** reject nesting exceeding the configured depth limit (default `64`) with `DEPTH`.

### 3.3 Worked Examples (Informative)

- **`Point { x: i32, y: i32 }`** with `x = 9, y = -4` (`spec/golden/point.kiln`, 8 bytes):
  ```text
  09 00 00 00   fc ff ff ff
  └─ x = 9 ─┘   └─ y = -4 ┘
  ```
- **`Message`** (`spec/golden/message.kiln`, 37 bytes) with `f_bool=true, f_int32=-2, f_int64=99, f_float64=1.5, f_string="hi", f_bool_2=false, f_int32_2=7, f_string_2="z"`:
  ```text
  01                         bool(true)
  fe ff ff ff                i32(-2)
  63 00 00 00 00 00 00 00    i64(99)
  00 00 00 00 00 00 f8 3f    f64(1.5)
  02 00 00 00 68 69          str("hi")
  00                         bool(false)
  07 00 00 00                i32(7)
  01 00 00 00 7a             str("z")
  ```

---

## 4. Lengths, Caps, and Pre-Allocation Bounds {#lengths-and-allocation}

### 4.1 Wire Maxima vs. Implementation Caps

- **Wire maxima:** A Frozen `u32` count or byte length permits up to `2³² − 1` (`4,294,967,295`). A `KLNT` tensor `payload_bytes` or `byte_length` is a `u64` permitting up to `2⁶⁴ − 1`.
- **Implementation caps:** An implementation **SHOULD** expose configurable count and byte caps at or below the wire maxima. The reference conformance cap used by `spec/kiln-v2-cases.json` is `16,777,216` elements (and `16 MiB` for a single string/byte run where applicable).
- **View vs. owned copy:** The count/byte cap **MUST NOT** reject a tensor payload returned as a zero-copy view of a caller-supplied buffer already resident in memory. An owned copy **MAY** reject a payload exceeding its configured byte cap with `LIMIT` after verifying that the block fits in the buffer.

### 4.2 Pre-Allocation Guard for Counted Containers

Before allocating element storage for any `list<T>` or `dict<str,V>`, a conforming decoder **MUST** read the 4-byte `count` and execute the following steps in order:

1. If fewer than 4 unread bytes remain for the count word itself, raise `EOF`.
2. If `count > max_count`, raise `LIMIT`.
3. Let `m` be the minimum valid encoded byte size of one element (for `list<T>`, `m = min(T)`; for `dict<str,V>`, `m = 4 + min(V)`). If `m > 0` and `count × m` overflows unsigned 64-bit arithmetic (`count > ⌊(2⁶⁴ − 1) / m⌋`), raise `LIMIT`.
4. Let `remaining` be the number of unread bytes after the count word. If `count × m > remaining`, raise `EOF` **without allocating element storage**.
5. Only after steps 1–4 succeed **MAY** the decoder allocate storage proportional to `count`. Individual elements may still exceed `m` and fail later with their own error (`EOF`, `LIMIT`, `TYPE`, `UTF8`, or `DEPTH`).

For a `str` or `bytes` value, the decoder **MUST** check the `u32` length `n` against `max_bytes` (`LIMIT`) and `n ≤ remaining` (`EOF`) before allocating body storage.

### 4.3 Minimum Wire Size Function `min(T)`

| Type `T` | `min(T)` (bytes) |
| --- | ---: |
| `bool`, `i8`, `u8` | `1` |
| `i16`, `u16` | `2` |
| `i32`, `u32`, `f32` | `4` |
| `i64`, `u64`, `int`, `uint`, `f64` | `8` |
| `str`, `bytes`, `list<T>`, `dict<str,V>` | `4` |
| `opt<T>` | `1` |
| `tensors` | `64` |
| `struct` with fields `f₁ … fₖ` | `∑ min(type(fᵢ))` (`0` if `k = 0`) |

An empty struct has `min(T) = 0`, so step 4 does not bound `list<EmptyStruct>`; step 2 (`max_count`) bounds that allocation.

### 4.4 Pre-Allocation Guard for Tensor Directories

For a `KLNT` directory, the decoder **MUST NOT** allocate descriptor arrays or payload copies until:

1. `tensor_count ≤ max_count` and `name_bytes ≤ max_count` (`LIMIT`),
2. `tensor_count × 128 + name_bytes` does not overflow `u64` (`LIMIT`) and equals `directory_bytes` (`TYPE`),
3. `64 + directory_bytes ≤ len(buf)` (`EOF`), and
4. `payload_base + payload_bytes` does not overflow `u64` (`LIMIT`) and `payload_base + payload_bytes ≤ len(buf)` (`EOF`).

---

## 5. Framing, Profiles, and Schema Hash {#frame}

### 5.1 Profile Registry {#profiles}

The frame profile byte identifies the top-level record layout. The tensor directory is **not** a separate frame profile; it is an embedded Frozen value (`tensors`).

| Code | Name | Version 2 Status |
| ---: | --- | --- |
| `0` | Frozen | **Normative.** Default and sole frame profile accepted in Version 2. |
| `1` | Evolve | Reserved (experimental; rejected with `FRAME` in Version 2). |
| `2` | View | Reserved (API access mode over Frozen bytes; not a wire profile). |
| `3` | Tensor | Reserved (superseded by embedded `tensors` value with `KLNT` v2 header). |
| `4` | Columns | Reserved (excluded from Version 2; rejected with `FRAME`). |

All profile codes `≥ 5` are reserved and **MUST** be rejected with `FRAME`.

### 5.2 Frame Header (`KLN0`) {#frame-header}

An optional frame prefixes exactly **one** Frozen value with a 16-byte header. Multi-byte fields are little-endian.

| Offset | Size | Field | Normative Constraint |
| ---: | ---: | --- | --- |
| `0` | `4` | `magic` | ASCII `KLN0` (`4B 4C 4E 30`). |
| `4` | `1` | `profile` | `u8`. **MUST** be `0` (Frozen). |
| `5` | `1` | `flags` | `u8`. **MUST** be `0` in Version 2. |
| `6` | `2` | `reserved` | `u16`. **MUST** be `0` in Version 2. |
| `8` | `8` | `schema_hash` | `u64` LE FNV-1a-64 hash of the root value's canonical type tokens (§5.3). |

**Frame validation order:**

1. Fewer than 4 bytes → `EOF`.
2. Bytes `0..3 ≠ "KLN0"` → `FRAME`.
3. Fewer than 16 bytes → `EOF`.
4. `profile ≠ 0`, `flags ≠ 0`, or `reserved ≠ 0` → `FRAME`.
5. `schema_hash ≠ type_hash(expected_type)` → `SCHEMA` (before reading byte 16).
6. Decode exactly one Frozen value starting at offset `16`. Unread trailing bytes → `TRAILING`.

### 5.3 Canonical Type Text and Schema Hash {#schema-hash}

The schema hash is the 64-bit **FNV-1a** digest [\[FNV\]](#references) over a deterministic sequence of `0x00`-terminated ASCII/UTF-8 tokens derived from the static type.

#### Algorithm

Initialize `h` as an unsigned 64-bit integer:

```text
FNV_OFFSET = 14695981039346656037   (0xCBF29CE484222325)
FNV_PRIME  = 1099511628211          (0x00000100000001B3)

function mix_token(h: u64, token: bytes) -> u64:
    for b in token:
        h = ((h XOR u64(b)) * FNV_PRIME) mod 2^64
    # Trailing 0x00 delimiter (XOR with 0 is identity):
    h = (h * FNV_PRIME) mod 2^64
    return h
```

Every emitted token is passed individually to `mix_token`, so a `0x00` separator step is mixed after **every** token. This prevents boundary ambiguity between adjacent identifiers and delimiters.

#### Token Emission Grammar

Let `tokens(T)` denote the ordered list of byte strings fed to `mix_token`:

```ebnf
tokens(bool)          ::= ["bool"]
tokens(i8)            ::= ["i8"]
tokens(i16)           ::= ["i16"]
tokens(i32)           ::= ["i32"]
tokens(i64)           ::= ["i64"]
tokens(int)           ::= ["int"]
tokens(u8)            ::= ["u8"]
tokens(u16)           ::= ["u16"]
tokens(u32)           ::= ["u32"]
tokens(u64)           ::= ["u64"]
tokens(uint)          ::= ["uint"]
tokens(f32)           ::= ["f32"]
tokens(f64)           ::= ["f64"]
tokens(str)           ::= ["str"]
tokens(tensors)       ::= ["tensors"]

tokens(list<T>)       ::= ["list<"]  ++ tokens(T) ++ [">"]
tokens(opt<T>)        ::= ["opt<"]   ++ tokens(T) ++ [">"]
tokens(dict<str,V>)   ::= ["dict<str,"] ++ tokens(V) ++ [">"]

tokens(struct{f₁:T₁, …, fₖ:Tₖ}) ::=
    ["struct{"]
    ++ concat_{i=1..k}( [utf8(name(fᵢ)), ":"] ++ tokens(Tᵢ) ++ [","] )
    ++ ["}"]
```

Notes:
- For `tensors`, only the single token `"tensors"` is mixed; tensor dtypes, ranks, shapes, and names inside a directory are runtime data and are **NOT** part of the schema hash.
- A JSON Schema binary string (`"type": "string", "format": "binary"`) maps to `list<u8>` in typed codecs, emitting `["list<", "u8", ">"]`.
- Struct field names are mixed in declaration order as raw UTF-8 bytes.

#### Worked Verification Vectors

1. **`struct{id:i64,batch:tensors,}`** (case `kiln-v2-framed`, 88 bytes):
   - Token stream (10 tokens): `["struct{", "id", ":", "i64", ",", "batch", ":", "tensors", ",", "}"]`
   - Digest: `0xe58aadc7552f0d82` → frame header: `4b 4c 4e 30 00 00 00 00 82 0d 2f 55 c7 ad 8a e5`
2. **`Point`** (`struct{x:i32,y:i32,}`):
   - Token stream (10 tokens): `["struct{", "x", ":", "i32", ",", "y", ":", "i32", ",", "}"]`
   - Digest: `0xe66ac0386103c72f` → LE bytes: `2f c7 03 61 38 c0 6a e6`
3. **`Message`** (`spec/golden/message.frame.kiln`, 53 bytes):
   - Digest: `0xd6646445f41ce803` → frame header: `4b 4c 4e 30 00 00 00 00 03 e8 1c f4 45 64 64 d6`

---

## 6. Tensor Directory (`KLNT`, Version 2) {#tensor-directory}

A tensor directory holds zero or more typed, shaped numeric arrays in a single self-delimiting binary block.

### 6.1 Header (64 bytes) {#header}

Multi-byte fields are little-endian.

| Offset | Size | Field | Type & Normative Constraint |
| ---: | ---: | --- | --- |
| `0` | `4` | `magic` | ASCII `KLNT` (`4B 4C 4E 54`). |
| `4` | `1` | `version` | `u8`. **MUST** be `2`. Any other value → `FRAME`. |
| `5` | `1` | `flags` | `u8` bitmask: bit `0` (`0x01`) = `FLAG_NAME`; bit `1` (`0x02`) = `FLAG_LE` (**MUST** be `1`). Bits `2..7` **MUST** be `0`. Unknown bit or clear bit `1` → `FRAME`. |
| `6` | `2` | `reserved0` | `u16`. **MUST** be `0`, else `FRAME`. |
| `8` | `4` | `tensor_count` | `u32`. Number of 128-byte descriptors. |
| `12` | `4` | `name_bytes` | `u32`. Byte length of the name heap. |
| `16` | `8` | `payload_bytes` | `u64`. Total byte length of the payload region, including alignment gaps. |
| `24` | `8` | `directory_bytes` | `u64`. **MUST** equal `tensor_count × 128 + name_bytes` (else `TYPE`; overflow → `LIMIT`). |
| `32` | `32` | `reserved1` | 32 bytes. **MUST** all be `0x00`, else `FRAME`. |

An empty directory (`kiln-v2-empty`, 64 bytes) has `flags = 0x02` (`FLAG_LE` set, `FLAG_NAME` clear) and all length fields zero:

```text
4b4c4e54 02 02 0000 00000000 00000000 0000000000000000 0000000000000000 [32 × 00]
```

### 6.2 Sections and Alignment {#sections}

Let `align64(x) = (x + 63) & ~63` (the smallest multiple of 64 greater than or equal to `x`). A directory consists of five contiguous regions:

| Region | Start Offset (from directory start) | Length (bytes) |
| --- | --- | --- |
| Header | `0` | `64` |
| Descriptors | `64` | `tensor_count × 128` |
| Name heap | `64 + tensor_count × 128` | `name_bytes` |
| Alignment padding | `64 + directory_bytes` | `payload_base − (64 + directory_bytes)` |
| Payloads | `payload_base = align64(64 + directory_bytes)` | `payload_bytes` |

- Total block length: `block_end = payload_base + payload_bytes` (overflow in `u64` → `LIMIT`).
- Every byte in the alignment padding region **MUST** be `0x00`; any nonzero byte **MUST** raise `TYPE` (case `kiln-v2-nonzero-pad`).

### 6.3 Tensor Descriptor (128 bytes) {#descriptor}

Each descriptor occupies 128 bytes. Multi-byte fields are little-endian.

| Offset | Size | Field | Type & Normative Constraint |
| ---: | ---: | --- | --- |
| `0` | `2` | `dtype` | `u16` code (§6.5). |
| `2` | `1` | `rank` | `u8` in `0..8`. `rank > 8` → `TYPE`. |
| `3` | `1` | `reserved0` | `u8`. **MUST** be `0`, else `FRAME`. |
| `4` | `2` | `name_off` | `u16` byte offset into name heap, or `0xFFFF` if unnamed. |
| `6` | `2` | `name_len` | `u16` byte length of tensor name, or `0` if unnamed. |
| `8` | `2` | `layout_off` | `u16` byte offset of opaque layout name in name heap, or `0xFFFF` if absent. |
| `10` | `2` | `layout_len` | `u16` byte length of layout name, or `0` if absent. |
| `12` | `4` | `block_size` | `u32`. `≥ 1` for opaque dtypes (§6.7); **MUST** be `0` for dtypes `1..19`. |
| `16` | `2` | `quant_scheme` | `u16` in `{0, 1, 2}` (§6.6). Other values → `TYPE`. |
| `18` | `2` | `quant_axis` | `u16` dimension index `< rank`, or `0xFFFF` when `quant_scheme == 0`. |
| `20` | `4` | `group_size` | `u32` `≥ 1` for schemes `1..2`, or `0` when `quant_scheme == 0`. |
| `24` | `4` | `scale_index` | `u32` descriptor index of scale tensor, or `0xFFFFFFFF` when `quant_scheme == 0`. |
| `28` | `4` | `outer_index` | `u32` descriptor index of outer scale tensor (scheme `2`), or `0xFFFFFFFF` otherwise. |
| `32` | `8` | `byte_offset` | `u64` offset from `payload_base`. |
| `40` | `8` | `byte_length` | `u64` byte length of this tensor's payload. |
| `48` | `64` | `shape[0..7]` | Eight `u64` dimension lengths. |
| `112` | `16` | `reserved1` | 16 bytes. **MUST** all be `0x00`, else `FRAME`. |

**Shape and range invariants:**

1. **Element count `n`:** For `rank == 0` (scalar), `n = 1`. For `rank ≥ 1`, `n = ∏_{i=0}^{rank−1} shape[i]` computed in unsigned 64-bit arithmetic; overflow **MUST** raise `LIMIT` (case `kiln-v2-shape-overflow`). A zero dimension (`shape[i] == 0`) is valid and yields `n = 0`.
2. **Unused shape tail:** For all `i` with `rank ≤ i < 8`, `shape[i]` **MUST** be `0`; any nonzero tail slot **MUST** raise `TYPE` (case `kiln-v2-shape-tail`).
3. **Payload bounds & non-overlap:** For every descriptor, `byte_offset + byte_length` **MUST NOT** overflow `u64` (`LIMIT`) and **MUST** satisfy `byte_offset + byte_length ≤ payload_bytes` (`TYPE`). For every distinct pair `(a, b)` of descriptors with nonzero lengths, the half-open ranges `[byte_offset_a, byte_offset_a + byte_length_a)` and `[byte_offset_b, byte_offset_b + byte_length_b)` **MUST NOT** overlap (`TYPE`, case `kiln-v2-overlap`). Zero-length ranges do not overlap any range.

### 6.4 Name Heap {#names}

1. **All-or-none naming (`FLAG_NAME`, bit 0):**
   - `FLAG_NAME` **MUST** be `1` if and only if at least one tensor has a name.
   - When `FLAG_NAME == 0`, every descriptor **MUST** have `name_len == 0` and `name_off == 0xFFFF`.
   - When `FLAG_NAME == 1`, `tensor_count` **MUST** be `≥ 1` and every descriptor **MUST** have `name_len ≥ 1` and `name_off ≠ 0xFFFF`. Setting `FLAG_NAME` on an empty directory **MUST** raise `TYPE` (case `kiln-v2-empty-name-flag`). Mixed named/unnamed directories are prohibited.
2. **Layout names:** Independent of `FLAG_NAME`. When `layout_len == 0`, `layout_off` **MUST** be `0xFFFF` (`TYPE`). When `layout_len ≥ 1`, `layout_off + layout_len ≤ name_bytes` (`TYPE`).
3. **Encoding and uniqueness:** Every tensor name and every layout name **MUST** be valid UTF-8 [\[RFC3629\]](#references) (else `UTF8`, case `kiln-v2-bad-utf8`). Tensor names **MUST** be unique as raw byte sequences (`TYPE`, case `kiln-v2-duplicate-name`). Layout names **MAY** repeat.
4. **Canonical heap order:** The name heap **MUST** equal the exact gapless concatenation of all tensor names in descriptor order (`0 .. tensor_count − 1`), followed by all layout names in descriptor order (`0 .. tensor_count − 1`). Any gap, extra byte, or out-of-order slice **MUST** raise `TYPE`.

### 6.5 Element Data Types (Dtypes) {#dtypes}

| Code Range | Category | Normative Behavior |
| --- | --- | --- |
| `0` | Invalid | **MUST** reject with `TYPE` (`kiln-v2-dtype-zero`). |
| `1..19` | Standard closed set | Validated per table below. |
| `20..4095` | Reserved | **MUST** reject with `TYPE` (`kiln-v2-dtype-reserved`). |
| `4096..32767` | Opaque layouts | Validated per §6.7. |
| `32768..65535` | Invalid | **MUST** reject with `TYPE`. |

**Standard Dtype Table (`1..19`):**

| Code | Name | Representation | `byte_length` for `n` elements |
| ---: | --- | --- | --- |
| `1` | `f64` | IEEE 754 binary64, LE | `8n` |
| `2` | `f32` | IEEE 754 binary32, LE | `4n` |
| `3` | `f16` | IEEE 754 binary16, LE | `2n` |
| `4` | `bf16` | 1 sign, 8 exponent (bias 127), 7 significand bits, LE | `2n` |
| `5` | `f8e4m3` | OCP OFP8 E4M3 [\[OFP8\]](#references) | `n` |
| `6` | `f8e5m2` | OCP OFP8 E5M2 [\[OFP8\]](#references) | `n` |
| `7` | `bool` | `0x00` or `0x01`; any byte `≥ 0x02` → `TYPE` (`kiln-v2-bool-byte`) | `n` |
| `8` | `i8` | Signed 8-bit two's complement | `n` |
| `9` | `u8` | Unsigned 8-bit | `n` |
| `10` | `i16` | Signed 16-bit two's complement, LE | `2n` |
| `11` | `u16` | Unsigned 16-bit, LE | `2n` |
| `12` | `i32` | Signed 32-bit two's complement, LE | `4n` |
| `13` | `u32` | Unsigned 32-bit, LE | `4n` |
| `14` | `i64` | Signed 64-bit two's complement, LE | `8n` |
| `15` | `u64` | Unsigned 64-bit, LE | `8n` |
| `16` | `i4` | Packed 4-bit two's complement (`−8..7`), low nibble first | `⌈n / 2⌉` |
| `17` | `u4` | Packed 4-bit unsigned (`0..15`), low nibble first | `⌈n / 2⌉` |
| `18` | `e2m1` | OCP MX FP4 E2M1 [\[OCP-MX\]](#references), packed nibbles, low nibble first | `⌈n / 2⌉` |
| `19` | `e8m0` | OCP MX E8M0 scale byte [\[OCP-MX\]](#references) | `n` |

- For every standard dtype, `byte_length` **MUST** equal the exact formula above (else `TYPE`, case `kiln-v2-length-mismatch`; `u64` multiplication overflow → `LIMIT`).
- For `i4`, `u4`, and `e2m1`, element `0` is the low nibble of byte `0` and element `1` is the high nibble of byte `0`. Example (`kiln-v2-u4`): values `[1, 2, 3]` encode as `21 03`.
- A conforming reader **MAY** return `f8e4m3`, `f8e5m2`, `e2m1`, and `e8m0` payloads as raw bits without numeric conversion.

### 6.6 Quantization Links {#quantization}

Quantization metadata links a data tensor to sibling scale tensors in the same directory. Decoders **MUST** verify the structural invariants below and **MUST NOT** modify or dequantize payload bits.

| Scheme | Name | Required Descriptor Constraints |
| ---: | --- | --- |
| `0` | None | `quant_axis == 0xFFFF`, `group_size == 0`, `scale_index == 0xFFFFFFFF`, `outer_index == 0xFFFFFFFF`. |
| `1` | Block scales | `rank ≥ 1`, `quant_axis < rank`, `group_size ≥ 1`, valid `scale_index`, `outer_index == 0xFFFFFFFF`. |
| `2` | Block + outer scale | All Scheme 1 constraints, plus valid `outer_index`. |

**Structural invariants for Schemes 1 and 2 (violation → `TYPE`, overflow → `LIMIT`):**

1. **Distinct sibling scale:** `scale_index < tensor_count` and `scale_index ≠ self_index`.
2. **No scale chains:** `tensors[scale_index].quant_scheme` **MUST** be `0`.
3. **Group count match:** Let `a = quant_axis` and `g = group_size`. The element count of `tensors[scale_index]` **MUST** equal:
   ```text
   n_scales = ceil(shape[a] / g) * product(shape[i] for i in 0..rank-1, i != a)
   ```
   (where the empty product for `rank == 1` is `1`, and `ceil(0 / g) = 0`). Mismatch **MUST** raise `TYPE` (case `kiln-v2-scale-count`). The dtype of `tensors[scale_index]` is not restricted by the scheme (e.g., `e8m0` for MXFP4 in `kiln-v2-scales`, `f8e4m3` in `kiln-v2-scales-outer`).
4. **Outer scale (Scheme 2 only):** `outer_index < tensor_count`, `outer_index ≠ self_index`, `outer_index ≠ scale_index`, `tensors[outer_index].quant_scheme == 0`, `tensors[outer_index].dtype == 2` (`f32`), and the element count of `tensors[outer_index]` **MUST** be `1`.

### 6.7 Opaque Layouts {#opaque-layouts}

Dtype codes `4096..32767` carry foreign block-encoded payloads (e.g., `Q4_K`) without requiring Kiln to specify their internal bit format:

- `layout_len` **MUST** be `≥ 1` and reference a valid UTF-8 layout identifier in the name heap (missing layout name → `TYPE`, case `kiln-v2-opaque-no-layout`).
- `block_size` **MUST** be `≥ 1` (`TYPE`).
- `byte_length` is explicit and **MUST** satisfy `byte_length mod block_size == 0` (`TYPE`). The shape product is still validated for `u64` overflow (`LIMIT`) and tail zeros (`TYPE`), but is **NOT** checked against an element byte width.
- Standard dtypes (`1..19`) **MUST** have `block_size == 0`, `layout_len == 0`, and `layout_off == 0xFFFF` (`TYPE`).

### 6.8 Canonical Layout {#canonical-layout}

Encoders **MUST** emit, and decoders **MUST** require, the following unique placement for any ordered tensor list:

1. **Descriptor order:** Preserved in caller-supplied order. (If a language maps a dictionary of tensors to a directory, keys are sorted lexicographically by UTF-8 bytes before directory construction; descriptors are not re-sorted inside the directory.)
2. **Name heap:** Concatenated per §6.4.
3. **Greedy 64-byte payload placement:** Initialize `end = 0`. For each tensor `t` in descriptor order `0 .. tensor_count − 1`:
   - `t.byte_offset` **MUST** equal `align64(end)` (else `TYPE`, case `kiln-v2-unaligned`).
   - Advance `end = t.byte_offset + t.byte_length`.
4. **Payload size and zero-filled gaps:** `payload_bytes` **MUST** equal the final `end` (`0` when `tensor_count == 0`). Every byte in `[0, payload_bytes)` not covered by any tensor's `[byte_offset, byte_offset + byte_length)` **MUST** be `0x00` (else `TYPE`).
5. **Reserved fields and flags:** All reserved bytes are `0x00`; `FLAG_LE` is `1`; `FLAG_NAME` is `1` iff tensors are named.

Example (`kiln-v2-f8-pair`, 385 bytes): two 1-byte tensors (`f8e4m3`, `f8e5m2`) sit at `byte_offset = 0` and `byte_offset = 64`, separated by 63 zero bytes (`payload_bytes = 65`).

### 6.9 Embedding in Frozen Structs {#embedding}

A `tensors` field in a Frozen struct writes one canonical `KLNT` v2 block inline at the field's position with no surrounding prefix or padding. Because the block length `block_end` is self-determined by its header, the next struct field begins immediately at `block_end`. Standalone step 12 (`TRAILING`) **MUST NOT** be applied to an embedded directory.

- `kiln-v2-in-struct` (208 bytes): `struct{id:i64,batch:tensors,}` = 8-byte `i64(7)` (`07 00 00 00 00 00 00 00`) followed immediately by the 200-byte `kiln-v2-f32` block.
- `kiln-v2-framed` (88 bytes): 16-byte `KLN0` frame + 8-byte `i64(7)` + 64-byte `kiln-v2-empty` block.

---

## 7. Deterministic Validation Order and Error Model {#errors}

### 7.1 Wire Error Codes

Conforming decoders **MUST** report failures using this closed set of eight wire error codes:

| Code | Trigger Conditions |
| --- | --- |
| `FRAME` | Invalid magic (`KLN0` or `KLNT`), unsupported frame profile or directory version (`≠ 2`), unknown flag bit, clear `FLAG_LE` bit, or nonzero reserved byte in a frame header, directory header, or descriptor. |
| `SCHEMA` | `KLN0` frame `schema_hash` does not match the expected destination type (also used for malformed JSON Schema inputs in §8). |
| `LIMIT` | A count or byte length exceeds the configured implementation cap, or a size/offset/shape arithmetic operation overflows `u64`. |
| `EOF` | Input ends before a header, fixed-width value, checked length, directory, or payload fits in the remaining bytes. |
| `TYPE` | Structural or domain fault inside a recognized block: `bool` or `opt` tag `≥ 2`, unsorted/duplicate `dict` key, `directory_bytes` mismatch, bad `FLAG_NAME` / name-heap layout / duplicate tensor name, invalid dtype/rank/shape tail, payload range out-of-bounds or overlapping, non-canonical offset, nonzero padding/gap, nonzero odd packed high nibble, or invalid quantization/opaque metadata. |
| `UTF8` | Invalid UTF-8 byte sequence in a Frozen `str`, a tensor name, or an opaque layout name. |
| `TRAILING` | Standalone decode buffer contains unread bytes after the decoded value or directory ends. |
| `DEPTH` | Container nesting depth exceeds the configured limit (default `64`). |

*(Note: Implementations performing runtime range narrowing on dynamic values—e.g. encoding an `i64` into an `i8` schema field—MAY define a host-side `RANGE` error; it does not occur during typed wire decoding.)*

### 7.2 Tensor Directory Check Order {#check-order}

When a `KLNT` block contains multiple defects, a conforming decoder **MUST** report the **first** error encountered in this exact 12-step sequence (pinned by `spec/kiln-v2-cases.json`):

1. **Magic & header length:** Fewer than 4 bytes → `EOF`. Bytes `0..3 ≠ "KLNT"` → `FRAME`. Fewer than 64 bytes → `EOF`.
2. **Header envelope:** `version ≠ 2`, unknown flag bit (`flags & ~0x03 ≠ 0`), clear `FLAG_LE` (`flags & 0x02 == 0`), or any nonzero reserved header byte → `FRAME`.
3. **Header caps:** `tensor_count > max_count` or `name_bytes > max_count` → `LIMIT`.
4. **Directory arithmetic:** `tensor_count × 128 + name_bytes` overflows `u64` → `LIMIT`. Result `≠ directory_bytes` → `TYPE`.
5. **Directory fit (pre-allocation):** `64 + directory_bytes` overflows `u64` → `LIMIT`. Exceeds `len(buf)` → `EOF` (no descriptor array allocated).
6. **Block fit:** `payload_base = align64(64 + directory_bytes)` or `block_end = payload_base + payload_bytes` overflows `u64` → `LIMIT`. `block_end > len(buf)` → `EOF`.
7. **Header-to-payload padding:** Any nonzero byte in `[64 + directory_bytes, payload_base)` → `TYPE`.
8. **Descriptor reserved bytes & names:** Any nonzero descriptor reserved byte (`offset 3` or `112..127`) → `FRAME`. Validate `FLAG_NAME` consistency (`TYPE`), name/layout bounds (`TYPE`), UTF-8 validity (`UTF8`), tensor-name uniqueness (`TYPE`), and exact gapless heap concatenation (`TYPE`).
9. **Per-tensor metadata & ranges:** For each descriptor, check `byte_offset + byte_length` (`LIMIT` on overflow, `TYPE` if `> payload_bytes`), `rank ≤ 8` (`TYPE`), zero shape tail (`TYPE`), valid `dtype` (`TYPE`), element count (`LIMIT` on overflow), opaque vs. standard `layout`/`block_size`/`byte_length` (`TYPE`), and pairwise non-overlap (`TYPE`).
10. **Canonical placement & gap zeros:** Verify greedy `align64` offsets and final `end == payload_bytes` (`TYPE`), and verify every uncovered byte in `[0, payload_bytes)` is `0x00` (`TYPE`).
11. **Element bit domains & quantization:** Verify `bool` bytes `∈ {0, 1}` (`TYPE`), zero trailing high nibble for odd packed counts (`TYPE`), and all quantization link invariants from §6.6 (`TYPE`, or `LIMIT` on `u64` overflow).
12. **Standalone trailing check:** For a standalone directory buffer, `block_end ≠ len(buf)` → `TRAILING`. Suppressed when decoding a `tensors` struct field.

### 7.3 Trusted-Decoder Mode {#what-a-trusted-reader-may-skip}

A conforming decoder **MAY** provide an explicitly opted-in *trusted mode* for buffers produced within the same trust boundary (e.g., in-process IPC buffers just written by the caller):

- **Always required in safe trusted mode:** Bounds checks against the buffer length (`EOF`) MUST remain active unless the API is explicitly documented as memory-unsafe.
- **Permitted skips in trusted mode:** Skipping UTF-8 validation on strings/names, or skipping quantization group-count arithmetic on already-validated directories.
- **Explicit unsafe fast-cursor APIs:** A library **MAY** additionally expose unchecked low-level primitives that omit bounds checks altogether; such APIs are outside the conforming decoder class and **MUST** clearly document that passing untrusted input causes undefined memory access.

---

## 8. Portable JSON Schema Subset {#dynamic-values}

Code generators and runtime dynamic codecs targeting Kiln **SHOULD** support the following deterministic subset of JSON Schema [\[JSON-SCHEMA\]](#references). Generated structs **MUST** produce byte-identical Frozen encodings to hand-written structs with the same fields and declaration order.

| JSON Schema Construct | Kiln Canonical Type | Notes |
| --- | --- | --- |
| `{"type": "boolean"}` | `bool` | — |
| `{"type": "integer"}` (no `format`) | `i64` | Default integer width is 64-bit signed. |
| `{"type": "integer", "format": "int8"}` … `"int64"` | `i8`, `i16`, `i32`, `i64` | Signed fixed widths (`int8`, `int16`, `int32`, `int64`). |
| `{"type": "integer", "format": "uint8"}` … `"uint64"` | `u8`, `u16`, `u32`, `u64` | Unsigned fixed widths (`uint8`, `uint16`, `uint32`, `uint64`). |
| `{"type": "number"}` or `"format": "double"` | `f64` | Default floating-point width is binary64. |
| `{"type": "number", "format": "float"}` | `f32` | — |
| `{"type": "string"}` | `str` | — |
| `{"type": "string", "format": "binary"}` | `list<u8>` (`bytes`) | Wire-identical `u32` + raw bytes. |
| `{"type": "array", "items": S}` | `list<T>` | `T` is the mapping of `S`. |
| `{"type": "object", "properties": {…}}` | `struct` | Fields emitted in `properties` declaration order. If `required` is present, properties omitted from `required` become `opt<T>`; if `required` is absent, all properties are required (`T`). |
| `{"type": "object", "additionalProperties": S}` (no `properties`) | `dict<str,V>` | `V` is the mapping of `S`. Keys sorted per §3.1. |
| `{"$ref": "#/$defs/Name"}` | Referenced type | Local `#/$defs/` references only. Missing or cyclic `$ref` **MUST** raise `SCHEMA`. |

Unsupported keywords (e.g. `oneOf`, `anyOf`, `pattern`) and `tensors` fields are outside this subset; `tensors` fields are declared natively using the host language's tensor directory API.

---

## 9. Conformance Test Suite {#golden-cases}

Two artifact sets pin this specification to exact byte strings:

1. **Frozen golden binaries (`spec/golden/`):** Generated by `python3 spec/reference/gen_golden.py` (`point.kiln`, `message.kiln`, `message.frame.kiln`).
2. **Version-2 conformance vectors (`spec/kiln-v2-cases.json`):** 46 hex-encoded accept/reject test vectors generated and self-checked by `python3 spec/reference/gen_v2_cases.py` at reference cap `16,777,216`. Generation aborts if any vector diverges from its recorded result or error code.

| Case ID | Expected | Normative Rule Verified |
| --- | --- | --- |
| `kiln-v2-empty` | accept | Header-only empty directory (64 bytes, `FLAG_LE` set, `FLAG_NAME` clear) |
| `kiln-v2-f32` | accept | Single unnamed `f32` vector `[1.0, -2.0]`, 128-byte descriptor, LE bits |
| `kiln-v2-f32-scalar` | accept | Rank-0 scalar (`n = 1`, all 8 shape slots zero) |
| `kiln-v2-f32-negzero` | accept | IEEE 754 negative zero sign bit (`00 00 00 80`) |
| `kiln-v2-f64-nan` | accept | Quiet NaN payload preservation (`0x7FF8000000000001` LE) |
| `kiln-v2-f16-named` | accept | `f16(1.0)`, `FLAG_NAME`, name heap, and zero alignment padding |
| `kiln-v2-bf16` | accept | `bf16(1.0)` (`80 3f`) |
| `kiln-v2-i8` | accept | Two's-complement `i8` |
| `kiln-v2-bool` | accept | 1-byte `bool` payload (`0x00`/`0x01`) |
| `kiln-v2-u4` | accept | Packed nibbles, low nibble first (`[1, 2, 3]` → `21 03`) |
| `kiln-v2-f8-pair` | accept | `f8e4m3` + `f8e5m2` with canonical 64-byte offset gap |
| `kiln-v2-scales` | accept | Quantization Scheme 1 (MXFP4: 32 `e2m1` + 1 `e8m0`) |
| `kiln-v2-scales-outer` | accept | Quantization Scheme 2 (16 `e2m1` + 1 `f8e4m3` + 1 outer `f32`) |
| `kiln-v2-opaque` | accept | Opaque dtype `4096`, layout `"Q4_K"`, `block_size = 18` |
| `kiln-v2-in-struct` | accept | Embedded `tensors` field after `i64` in Frozen struct |
| `kiln-v2-framed` | accept | `KLN0` frame hash (`0xe58aadc7552f0d82`) covering `tensors` token |
| `kiln-pod-list-f32` | accept | Frozen `list<f32>` pre-allocation check passes (`[1.0, -2.0]`) |
| `kiln-v2-bad-magic` | `FRAME` | Invalid directory magic |
| `kiln-v2-bad-version` | `FRAME` | Directory version `≠ 2` (version 1 rejected) |
| `kiln-v2-empty-name-flag` | `TYPE` | `FLAG_NAME` set on empty directory |
| `kiln-v2-le-clear` | `FRAME` | `FLAG_LE` bit clear |
| `kiln-v2-unknown-flag` | `FRAME` | Reserved header flag bit set |
| `kiln-v2-reserved` | `FRAME` | Nonzero reserved header byte |
| `kiln-v2-directory-eof` | `EOF` | Claimed directory extends past buffer (pre-allocation reject) |
| `kiln-v2-count-cap` | `LIMIT` | `tensor_count = 16,777,217` exceeds reference cap |
| `kiln-v2-directory-mismatch` | `TYPE` | `directory_bytes ≠ tensor_count × 128 + name_bytes` |
| `kiln-v2-shape-overflow` | `LIMIT` | `u64` overflow in shape product |
| `kiln-v2-length-mismatch` | `TYPE` | `byte_length ≠ expected_bytes(dtype, n)` |
| `kiln-v2-overlap` | `TYPE` | Overlapping payload byte ranges |
| `kiln-v2-unaligned` | `TYPE` | Payload offset violates canonical `align64` placement |
| `kiln-v2-nonzero-pad` | `TYPE` | Nonzero byte in alignment padding |
| `kiln-v2-duplicate-name` | `TYPE` | Duplicate tensor names in heap |
| `kiln-v2-bad-utf8` | `UTF8` | Invalid UTF-8 bytes in tensor name |
| `kiln-v2-bool-byte` | `TYPE` | `bool` element byte `0x02` |
| `kiln-v2-scale-count` | `TYPE` | Quantization scale element count mismatch |
| `kiln-v2-opaque-no-layout` | `TYPE` | Opaque dtype missing layout name |
| `kiln-v2-trailing` | `TRAILING` | Unread bytes after standalone directory |
| `kiln-v2-high-nibble` | `TYPE` | Nonzero trailing high nibble on odd packed element count |
| `kiln-v2-shape-tail` | `TYPE` | Nonzero shape slot at index `≥ rank` |
| `kiln-v2-dtype-zero` | `TYPE` | Invalid dtype code `0` |
| `kiln-v2-dtype-reserved` | `TYPE` | Reserved dtype code `20` |
| `kiln-v2-payload-overflow` | `LIMIT` | `payload_base + payload_bytes` overflows `u64` |
| `kiln-list-struct-hostile` | `EOF` | `count = 16,777,216` structs with 0 trailing bytes (inside cap, fails pre-alloc) |
| `kiln-list-struct-short` | `EOF` | Two `i64` structs claimed, only 8 bytes remain |
| `kiln-list-str-short` | `EOF` | Three `str` claimed (`min = 4`), only 4 bytes remain |
| `kiln-pod-list-short` | `EOF` | Two `f32` claimed, only 4 payload bytes remain |

---

## Appendix A. Summary of Normative Changes from Draft v0 {#corrections-in-this-version}

| Area | Change in Version 2 |
| --- | --- |
| **Pre-allocation guard** | Extended `count × min(T) ≤ remaining` normatively from POD numeric lists to all lists, dicts, and tensor directories before any element allocation. |
| **Mandatory little-endian** | Clarified that direct memory copy is conforming only on little-endian hosts; big-endian hosts MUST byte-swap or refuse before writing. |
| **Wire maxima vs. library caps** | Separated `u32`/`u64` wire maxima from configurable implementation caps (with `16,777,216` / `16 MiB` retained only as reference defaults, not format limits). |
| **Tensor directory** | Replaced the experimental v1 `Float64`-only block with the canonical multi-tensor v2 `KLNT` directory embedded as Frozen type `tensors`; version `≠ 2` is rejected with `FRAME`. |

---

## Appendix B. Normative References {#references}

- **\[RFC2119\]** S. Bradner, *Key words for use in RFCs to Indicate Requirement Levels*, BCP 14, RFC 2119, March 1997. <https://www.rfc-editor.org/rfc/rfc2119>
- **\[RFC8174\]** B. Leiba, *Ambiguity of Uppercase vs Lowercase in RFC 2119 Key Words*, BCP 14, RFC 8174, May 2017. <https://www.rfc-editor.org/rfc/rfc8174>
- **\[RFC3629\]** F. Yergeau, *UTF-8, a transformation format of ISO 10646*, STD 63, RFC 3629, November 2003. <https://www.rfc-editor.org/rfc/rfc3629>
- **\[IEEE754\]** IEEE Std 754-2019, *IEEE Standard for Floating-Point Arithmetic*, July 2019.
- **\[OFP8\]** Open Compute Project, *OCP 8-bit Floating Point Specification (OFP8)*, Version 1.0, 2023.
- **\[OCP-MX\]** Open Compute Project, *OCP Microscaling Formats (MX) Specification*, Version 1.0, 2023.
- **\[FNV\]** G. Fowler, L. C. Noll, K.-P. Vo, D. Eastlake, *The FNV Non-Cryptographic Hash Algorithm*, IETF Draft (FNV-1a 64-bit parameters).
- **\[JSON-SCHEMA\]** A. Wright et al., *JSON Schema: A Media Type for Describing JSON Documents*, Draft 2020-12.
