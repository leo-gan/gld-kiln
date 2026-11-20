# Mojo API Reference

Public interface exported by `kiln` (`src/kiln/__init__.mojo`, package `mojo-kiln` `0.3.0`, Mojo `1.1.0`). For normative byte rules, see the [Wire Specification (v2)](../spec/index.md).

---

## 1. Codec Functions

| Symbol | Signature & Behavior |
| --- | --- |
| `encode` | `encode[T](value: T, mut w: Writer, max_depth: Int = MAX_DEPTH) raises KilnError`<br>Resets `w.length = 0` and encodes `value` into `w`, reusing `w`'s buffer capacity. |
| `encode_append` | `encode_append[T](value: T, mut w: Writer, max_depth: Int = MAX_DEPTH) raises KilnError`<br>Appends one encoded `value` to `w` without clearing prior bytes. |
| `encode_bytes` | `encode_bytes[T](value: T, max_depth: Int = MAX_DEPTH) raises KilnError -> List[UInt8]`<br>Allocates a `Writer`, encodes `value`, and returns an owned byte list. |
| `encoded_size` | `encoded_size[T](value: T) -> Int`<br>Returns the exact byte length `encode` will emit for `value`. |
| `decode` | `decode[T, o](data: Span[UInt8, o], check_utf8: Bool = True, max_depth: Int = MAX_DEPTH, max_bytes: Int = MAX_BYTES, max_count: Int = MAX_COUNT) raises KilnError -> T`<br>Decodes one standalone value from `data`. Requires exact buffer consumption (`TRAILING`) and `T: Defaultable & Movable & Deinitable`. |
| `decode_bytes` | `decode_bytes[T](data: List[UInt8], check_utf8: Bool = True, max_depth: Int = MAX_DEPTH) raises KilnError -> T`<br>Convenience wrapper calling `decode[T](Span(data), check_utf8, max_depth)`. |
| `encode_framed` | `encode_framed[T](value: T, mut w: Writer, max_depth: Int = MAX_DEPTH) raises KilnError`<br>Resets `w` and emits the 16-byte `KLN0` header (profile `0`, FNV-1a-64 schema hash) followed by one Frozen value. |
| `decode_framed` | `decode_framed[T, o](data: Span[UInt8, o], check_utf8: Bool = True, max_depth: Int = MAX_DEPTH) raises KilnError -> T`<br>Validates the `KLN0` header and `type_hash[T]()` (`SCHEMA` on mismatch), then decodes the single Frozen value. |
| `type_hash` | `type_hash[T]() -> UInt64`<br>Computes the normative FNV-1a-64 schema digest for `T` ([Spec §5.3](../spec/index.md#schema-hash)). |

---

## 2. Buffer and Cursor Types

### `Writer`

Reusable little-endian byte sink (`kiln.wire.Writer`):

- **Constructor:** `Writer(capacity: Int = 256)` (clamped to at least 64 bytes).
- **Configurable limits:** `max_depth` (`64`), `max_bytes` (`16_777_216`), `max_count` (`16_777_216`).
- **Key methods:** `reset()`, `ensure(extra: Int)`, `reserve(n: Int) -> Int`, `copy_bytes() -> List[UInt8]`, and primitive emitters `put_u8`, `put_u16`, `put_u32`, `put_u64`, `put_i32`, `put_i64`, `put_f32`, `put_f64`, `put_span`.

### `Reader[origin: ImmOrigin]`

Forward cursor over an immutable `Span[UInt8, origin]` (`kiln.wire.Reader`):

- **Constructor:** `Reader(data, check_utf8=True, max_depth=MAX_DEPTH, max_bytes=MAX_BYTES, max_count=MAX_COUNT)`.
- **Checked methods (safe on untrusted input):** `remaining()`, `u8()`, `u16()`, `u32()`, `u64()`, `i32()`, `i64()`, `f32()`, `f64()`, `boolean()`, `count()`, `take(n)`, `read_string() -> String`, and zero-copy `read_string_slice() -> StringSpan[origin]`.
- **Unchecked fast-cursor methods (unsafe on untrusted input):**
  - `u8_fast() -> UInt8`
  - `u32_fast() -> UInt32`
  - `u64_fast() -> UInt64`
  - `str_fast() -> StringSpan[origin]`

!!! warning "Safety contract for `Reader.*_fast`"
    These methods omit all bounds checks and UTF-8 validation. They exist solely for caller-guaranteed buffers (such as buffers encoded within the same process). Passing an untrusted or truncated buffer to `str_fast` or `u*_fast` can read past the end of the span and cause undefined memory behavior.

---

## 3. Custom Codec Traits

Built-in scalars, `String`, `List`, `Optional`, `Dict[String, V]`, `TensorDir`, and plain structs are handled automatically. User structs can override derived reflection by conforming to `KilnCodec` (and optionally `KilnMin`):

```mojo
trait KilnCodec:
    def kiln_encode(self, mut w: Writer) raises KilnError: ...
    def kiln_size(self) -> Int: ...
    @staticmethod
    def kiln_decode[o: ImmOrigin, po: MutOrigin](mut r: Reader[o], ptr: Pointer[Self, po]) raises KilnError: ...
    @staticmethod
    def kiln_hash(mut h: UInt64): ...

trait KilnMin:
    @staticmethod
    def kiln_min() -> Int: ...
```

- `kiln_size()` **MUST** equal the exact byte count written by `kiln_encode()`.
- If a `KilnCodec` type does not also conform to `KilnMin`, the pre-allocation guard defaults its minimum wire size to `1` byte.

---

## 4. Tensor Directory API

- **`TensorDir`**: Conforms to `KilnCodec` and `KilnMin` (`kiln_min() == 64`, schema hash token `"tensors"`). Holds `items: List[KilnTensor]`.
- **`KilnTensor`**: Descriptor + raw payload bytes (`dtype`, `rank`, `shape: List[UInt64]`, `name`, `layout`, `block_size`, `quant_scheme`, `quant_axis` (`-1` when none), `group_size`, `scale_index` (`-1` when none), `outer_index` (`-1` when none), `data: List[UInt8]`).
- **`f64_directory(data: List[Float64]) -> TensorDir`**: Wraps a `List[Float64]` as a single unnamed `f64` tensor via bulk little-endian copy.
- **Dtype constants:** Re-exported from `kiln`: `DTYPE_F64` (1), `DTYPE_F32` (2), `DTYPE_F16` (3), `DTYPE_BF16` (4), `DTYPE_F8E4M3` (5), `DTYPE_F8E5M2` (6), `DTYPE_BOOL` (7), `DTYPE_I8` (8), `DTYPE_I4` (16), `DTYPE_U4` (17), `DTYPE_E2M1` (18), `DTYPE_E8M0` (19). Integer constants `DTYPE_U8` (9) through `DTYPE_U64` (15), plus `OPAQUE_MIN` (4096) and `OPAQUE_MAX` (32767), are defined in `kiln.tensor`.

---

## 5. Dynamic Schema & Value API

- `schema_from_json(text: String) raises KilnError -> Schema` — parses the [JSON Schema subset](../spec/index.md#dynamic-values).
- `Value` — arena-backed dynamic value tree with builders `add_none`, `add_bool`, `add_i64`, `add_u64`, `add_f32`, `add_f64`, `add_str`, `add_bytes`, `start_list`, `start_struct`, `start_dict`, `push`, `add_entry`, and accessors `child`, `child_key`.
- `encode_value(schema, value, mut w, max_depth=MAX_DEPTH)`
- `encode_value_bytes(schema, value, max_depth=MAX_DEPTH) -> List[UInt8]`
- `decode_value(schema, data, check_utf8=True, max_depth=MAX_DEPTH) -> Value`

---

## 6. Errors and Default Implementation Limits

### `KilnError`

`KilnError(kind: Int, offset: Int)` records both the failure class and the byte offset in the input (or output) buffer where the fault was detected.

| Constant | Value | Meaning |
| --- | ---: | --- |
| `KilnError.EOF` | `1` | Unexpected end of input or pre-allocation bounds failure |
| `KilnError.RANGE` | `2` | Dynamic `Value` integer out of target schema width range during `encode_value` |
| `KilnError.UTF8` | `3` | Invalid UTF-8 in a string, tensor name, or layout name |
| `KilnError.TYPE` | `4` | Invalid bool/optional tag or `KLNT` structural/metadata/layout violation |
| `KilnError.DEPTH` | `5` | Nesting depth exceeds `max_depth` |
| `KilnError.LIMIT` | `6` | Count/length exceeds cap, or `u64` size/shape arithmetic overflow |
| `KilnError.SCHEMA` | `7` | `KLN0` frame schema hash mismatch or invalid JSON Schema |
| `KilnError.TRAILING` | `8` | Unread bytes after a standalone decoded value |
| `KilnError.FRAME` | `9` | Invalid magic, profile, directory version, flags, or reserved bytes |

### Default Caps & Constants

| Constant | Default | Meaning |
| --- | ---: | --- |
| `MAX_COUNT` | `16_777_216` | Default element/tensor count cap (`kiln.wire`) |
| `MAX_BYTES` | `16_777_216` | Default single string / byte-run cap (`16 MiB`, `kiln.wire`) |
| `MAX_DEPTH` | `64` | Default container nesting limit |
| `PROFILE_FROZEN` .. `PROFILE_COLUMNS` | `0..4` | Frame profile registry codes |

---

## 7. Conformance Notes (`mojo-kiln` v0.3.0)

`mojo-kiln` `0.3.0` passes all 46 vectors in `spec/kiln-v2-cases.json` and all Frozen golden binaries in `spec/golden/`. Relative to the strict Version 2 standard rules, three edge cases in `0.3.0` are currently looser and tracked for tightening:

1. **`decode_framed` header checks (`src/kiln/codec.mojo`):** Returns `FRAME` rather than `EOF` when `len(data) < 16`, and skips checking that frame `flags` (offset `5`) and `reserved` (offsets `6..7`) are zero.
2. **`Dict[String, V]` decoding (`src/kiln/codec.mojo`):** Encodes keys in canonical sorted UTF-8 order, but `Dict.read_into` does not yet reject unsorted/duplicate wire keys with `TYPE` or run `_guard_count` prior to loop iteration.
3. **Dynamic `decode_value` containers (`src/kiln/value.mojo`):** `TY_LIST` and `TY_DICT` validate `count ≤ max_count` via `r.count()` but do not yet run the minimum-size pre-allocation check before building `Value` nodes.
