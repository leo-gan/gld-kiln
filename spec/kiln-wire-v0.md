# Kiln wire format, version 2

Kiln is a positional little-endian encoding. The reader knows the type, so the bytes do not carry field names or field numbers. This text is the normative description. A tensor directory is a Frozen value. Its version is 2, and there is no earlier tensor layout.

`spec/reference/kiln_ref.py` is the reference codec for Frozen scalars, lists, and structs. The Mojo tests check the tensor directory and the allocation rule. The hex cases live in `spec/kiln-v2-cases.json`. The reference cap in those cases is 16,777,216, which is the Mojo library's default.

## What Kiln guarantees

Kiln is a positional little-endian encoding for a program that already knows the schema and that also moves numeric arrays. Four properties define the format. The sections after this one are the rules that make the properties hold.

**The numeric payload is the array.** A fixed-width number is stored as its little-endian bits. A list of those numbers is those bits in order. A tensor payload is the same kind of region, and each payload begins at an offset that is a multiple of 64 from the start of its directory. The directory is a table of fixed-width records: a dtype code, a rank, a shape, a byte offset, and a byte length. A reader checks the table and then uses the payload in place. A reader that was asked for an owned copy writes the payload once into the caller's buffer, or into a new buffer when the caller asked for one. A quantized block stays bits. Its scale is another tensor in the same directory. Kiln does not multiply them.

**The same value has the same bytes, and the schema is not in those bytes.** Fields are written in declaration order, with no name and no tag on the wire. Dict keys are written in lexicographic order of their UTF-8 bytes. Frozen inserts no padding. A floating-point value keeps every bit, including the payload of a NaN and the sign of zero. A tensor directory has one canonical layout, defined below, so two encoders of the same tensors write the same block. A frame may carry an FNV-1a 64-bit hash of the canonical type text. If the hash does not match the type the reader was given, the reader stops before the first field.

**A record and its arrays are one buffer.** The tensor directory is a Frozen value. Its canonical name is `tensors`. A struct field of that type is the directory block, and the next field begins at the end of the block. One message can hold an identifier, a string, and the arrays. The identifier and the string are stores and a length. The arrays are the directory and the payloads.

**A count cannot allocate past the bytes that remain.** The reader of a list, a dict, or a tensor directory computes how many bytes the claimed count requires at minimum. If that product overflows, or if it is larger than the unread portion of the buffer, the reader returns an error and does not allocate element storage. The check uses the schema, so it does not need to parse the elements first. A separate trusted reader may skip UTF-8 checking and the quant-shape arithmetic for a buffer this process has just written. It still rejects a length that would read past that buffer.

These four properties are the advantage over the formats that already solve one of these jobs. Safetensors puts raw arrays after a header, and that header is JSON, so a struct, a canonical record encoding, and the allocation rule are outside its job. Protobuf describes a struct by tagging and parsing each value. FlatBuffers and Cap'n Proto borrow fields by storing an offset with each field. GGUF carries quantized weights as a model file, with a sequential metadata preamble and ggml's block layouts. Kiln leaves the schema in the program, puts one hash in the frame, puts a length only on a value that has a length, and leaves the numeric payload as the array itself.

Schema evolution and columnar table scans stay outside this version. A changed struct fails the frame hash. A list of fixed-width numbers is already one contiguous column.

## Corrections in this version

Two correctness rules are part of this draft, and they apply to Frozen values as well as to the new directory. A third rule splits the old 16 MiB ceiling from the wire, because a tensor length is a `u64`.

**Allocation.** Before a decoder allocates storage for a count, it requires the unread bytes to hold the minimum legal encoding of that many elements. The check covers lists of numbers, strings, and structs, and it covers a tensor count. The cases `kiln-list-struct-hostile`, `kiln-list-struct-short`, `kiln-list-str-short`, `kiln-pod-list-short`, `kiln-v2-directory-eof`, `kiln-v2-count-cap`, and `kiln-v2-payload-overflow` pin it.

**Byte order.** Every multi-byte integer and every multi-byte numeric payload is little-endian on every host. Copying host memory into the wire image is conforming only when the host is little-endian and the host type has the same width and order as the wire type. On any other host the implementation byte-swaps, or it refuses the operation before it writes. A refusal is conforming. Writing host byte order and calling the result Kiln is not. The cases `kiln-v2-f32`, `kiln-v2-f32-negzero`, `kiln-v2-f64-nan`, `kiln-pod-list-f32`, and `kiln-v2-le-clear` pin the byte patterns and the flag.

**Limits.** A Frozen `u32` length or count has wire maximum 4,294,967,295. An implementation has a configurable cap at or below that maximum. The Mojo default is 16,777,216 counts and 16 MiB for one string or byte run until a caller raises it. A value above the cap is `LIMIT`. A value inside the cap that does not fit in the buffer is `EOF`. A tensor payload length is a `u64`. The count cap does not apply to a payload returned as a view of a buffer the caller already holds. An owned copy may refuse a payload above the configured byte cap with `LIMIT`, after the block has been checked to fit.

## Byte order

Multi-byte integers in Frozen and in both tensor headers are little-endian. IEEE `f16`, `f32`, and `f64`, and `bfloat16`, are little-endian. `f32` value 1.0 is the bytes `00 00 80 3f`. `f32` negative zero is `00 00 00 80`. The `f64` quiet NaN with payload 1 used in the golden cases is the bits `0x7FF8000000000001`, little-endian.

Single-byte dtypes, and the bytes of a packed nibble stream, may be copied on any host. A packed stream is still a sequence of bytes in wire order. The first element is the low nibble of the first byte.

The tensor directory sets flag bit 1, the little-endian bit. A reader rejects the block when that bit is clear. The bit does not select a byte order. It records that the payloads follow this section.

## Lengths and allocation

The reader consumes the count, then applies this check, then allocates.

1. If the count word itself does not fit, the error is `EOF`.
2. If the count is above the configured cap, the error is `LIMIT`. The default cap is 16,777,216. The check happens before any allocation whose size depends on the count.
3. Let `m` be the minimum wire size of one element, from the table below. If `m` is greater than 0 and `count * m` does not fit in an unsigned 64-bit integer, the error is `LIMIT`.
4. If `count * m` is greater than the number of unread bytes, the error is `EOF`. The reader does not allocate element storage.
5. Only a count that passes these steps may allocate. A later element may still be longer than the minimum and may then fail. That later failure is the element's own error.

| Element | Minimum bytes |
| --- | --- |
| `bool`, `i8`, `u8` | 1 |
| `i16`, `u16` | 2 |
| `i32`, `u32`, `f32` | 4 |
| `i64`, `u64`, `int`, `uint`, `f64` | 8 |
| `str`, `list<u8>` | 4 |
| `opt<T>` | 1 |
| `list<T>`, `dict<str,V>` | 4 |
| `tensors` | 64 |
| struct | Sum of the field minimums |

A struct with no fields has minimum 0. The product is then 0, so the byte check does not reject the count. The cap in step 2 is what bounds that allocation.

A string length is still checked against the unread bytes before the string body is allocated. The list rule is in addition to that check. It stops a count from reserving a slot per element when those elements cannot all be present.

The same idea bounds a tensor directory. The reader does not allocate one descriptor per claimed tensor until `tensor_count * 128 + name_bytes` lies inside the buffer, the product does not overflow, and `tensor_count` is within the cap. It does not allocate a payload of `payload_bytes` in order to decide that the block does not fit. A view borrows the caller's buffer. An owned copy allocates the payload only after the block end has been checked.

`payload_base + payload_bytes` is computed in unsigned 64-bit arithmetic. If the sum overflows, the error is `LIMIT`.

## Profiles

The directory is a Frozen value, not a separate frame profile.

| Code | Name | Status |
| --- | --- | --- |
| 0 | Frozen | Normative. This is the default. |
| 1 | Evolve | Still an experiment. Not the default API. |
| 2 | View | Still not a separate layout. A borrowed read uses the Frozen bytes. |
| 3 | Tensor | The Frozen value `tensors`. The directory version byte is 2. |
| 4 | Columns | Not in this version. |

## Frozen values

The scalar, string, list, optional, and dict encodings follow the table above, including sorted dict keys and the rule that Frozen inserts no padding.

One type is added.

| Canonical name | Encoding |
| --- | --- |
| `tensors` | One complete version-2 tensor directory, including its magic. The block length is determined by the header. The next field starts at the end of the block. |

A `tensors` value is a version-2 directory. Any other directory version is `FRAME`.

`decode` of a standalone value still requires the buffer to contain exactly that value. Nesting deeper than 64 containers is still a depth error.

## Schema hash

The hash is FNV-1a 64. The offset basis is 14695981039346656037 and the prime is 1099511628211. Each token is mixed one byte at a time, and each token is followed by the FNV step for a `0x00` byte.

The new token is `tensors`, mixed as those seven ASCII bytes and then the `0x00` step. The hash does not include the dtypes or the shapes inside the directory. Those are data.

For the type `struct{id:i64,batch:tensors,}` the hash is `0xe58aadc7552f0d82`. The framed golden case stores that value as a little-endian `u64` after the 8-byte frame prefix.

## Frame

The frame is sixteen bytes: magic `KLN0`, Frozen profile 0, flags 0, reserved 0, then the schema hash, then one Frozen value. A `tensors` field may appear in that value.

## Tensor directory

A directory holds zero or more tensors. Magic is `KLNT` and the version byte is 2. Any other version is `FRAME`. There is no other tensor layout.

### Header

The header is 64 bytes. Multi-byte fields are little-endian.

| Offset | Size | Name | Contents |
| --- | --- | --- | --- |
| 0 | 4 | magic | ASCII `KLNT` |
| 4 | 1 | version | 2 |
| 5 | 1 | flags | Bit 0 is the name bit. Bit 1 is the little-endian bit and must be set. Other bits are zero. |
| 6 | 2 | reserved | 0 |
| 8 | 4 | tensor_count | `u32` |
| 12 | 4 | name_bytes | `u32` length of the name heap |
| 16 | 8 | payload_bytes | `u64` length of the payload region, including alignment gaps |
| 24 | 8 | directory_bytes | `u64`. Must equal `tensor_count * 128 + name_bytes` |
| 32 | 32 | reserved | 0 |

`directory_bytes` is stored so a reader can check the count against the length without trusting either number alone. A mismatch is `TYPE`. An unknown flag bit, a clear little-endian bit, or a nonzero reserved byte is `FRAME`.

An empty directory has every length field zero. The little-endian flag is set and the name flag is clear. The block is the 64-byte header:

```text
4b4c4e54020200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
```

### Sections

The block is five regions, in this order.

| Region | Start | Length |
| --- | --- | --- |
| Header | 0 | 64 |
| Descriptors | 64 | `tensor_count * 128` |
| Name heap | 64 + `tensor_count * 128` | `name_bytes` |
| Padding | end of the heap | zeros up to the next multiple of 64, measured from the start of the block |
| Payloads | `payload_base` | `payload_bytes` |

`payload_base` is `(64 + directory_bytes + 63)` with the low 6 bits cleared. The block length is `payload_base + payload_bytes`. Padding bytes are `0x00`. A nonzero pad byte is `TYPE`.

One unnamed `f32` vector of length 2 occupies 200 bytes: a 64-byte header, one 128-byte descriptor, no heap, no pad, and 8 payload bytes. The payload is `00 00 80 3f 00 00 00 c0`, which is 1.0 and −2.0. `kiln-v2-f32` is that block.

### Descriptor

Each descriptor is 128 bytes.

| Offset | Size | Name | Contents |
| --- | --- | --- | --- |
| 0 | 2 | dtype | `u16` code from the dtype table |
| 2 | 1 | rank | 0 through 8 |
| 3 | 1 | reserved | 0 |
| 4 | 2 | name_off | Offset into the name heap, or `0xFFFF` when unnamed |
| 6 | 2 | name_len | Byte length of the name, or 0 when unnamed |
| 8 | 2 | layout_off | Offset of an opaque layout name, or `0xFFFF` |
| 10 | 2 | layout_len | Byte length of the layout name, or 0 |
| 12 | 4 | block_size | `u32`. Zero except for an opaque dtype |
| 16 | 2 | quant_scheme | 0, 1, or 2 |
| 18 | 2 | quant_axis | Dimension index, or `0xFFFF` when scheme is 0 |
| 20 | 4 | group_size | `u32`. Zero when scheme is 0 |
| 24 | 4 | scale_index | Index of the scale tensor, or `0xFFFFFFFF` |
| 28 | 4 | outer_index | Index of the outer scale tensor, or `0xFFFFFFFF` |
| 32 | 8 | byte_offset | `u64` offset from the start of the payload region |
| 40 | 8 | byte_length | `u64` |
| 48 | 64 | shape | Eight `u64` dimensions. Slots at and past `rank` are 0 |
| 112 | 16 | reserved | 0 |

Rank 0 is a scalar. Its element count is 1, and all eight shape slots are 0. Rank 1 or more has element count equal to the product of `shape[0]` through `shape[rank - 1]`. A zero dimension is legal. The product is computed so that overflow is `LIMIT`, not a wrapped count. A nonzero shape slot at or past the rank is `TYPE`.

The half-open ranges `[byte_offset, byte_offset + byte_length)` of two tensors must not overlap. A zero length does not overlap any range. A range that extends past `payload_bytes`, or whose end overflows a `u64`, is an error: overflow is `LIMIT`, and a range past the payload is `TYPE`.

### Names

The name flag is set exactly when at least one tensor has a name. When the flag is clear, every tensor has `name_len` 0 and `name_off` `0xFFFF`. When the flag is set, every tensor has a non-empty name. An empty directory therefore has the flag clear. A set flag on an empty directory is `TYPE`.

Layout names are independent of the flag. They occupy the same heap. Each name and each layout name is UTF-8. A bad sequence is `UTF8`. Tensor names are unique as raw bytes. Layout names may repeat.

The heap is exactly the concatenation of the tensor names in descriptor order, followed by the layout names in descriptor order. There is no gap and no extra byte. A hole, a reordered heap, or a slice that ends past `name_bytes` is `TYPE`.

### Check order

The golden cases use the first error from this order. A later fault in the same block is not what the case records.

1. Fewer than 4 bytes, or fewer than 64 bytes once the magic matches, is `EOF`. A wrong magic is `FRAME`.
2. A version other than 2, an unknown flag, a clear little-endian bit, or a nonzero reserved header field is `FRAME`.
3. `tensor_count` or `name_bytes` above the cap is `LIMIT`.
4. If `tensor_count * 128 + name_bytes` overflows, the error is `LIMIT`. If `directory_bytes` is not that sum, the error is `TYPE`.
5. If the directory does not lie inside the buffer, the error is `EOF`. The reader has not allocated one descriptor per count.
6. If `payload_base + payload_bytes` overflows, the error is `LIMIT`. If the block does not lie inside the buffer, the error is `EOF`.
7. A nonzero padding byte is `TYPE`.
8. A nonzero reserved byte in a descriptor is `FRAME`. Name and layout rules follow, including `UTF8`.
9. A payload range outside the payload region, a dtype or shape fault, or an overlapping range is `TYPE`. A shape product that overflows is `LIMIT`.
10. An offset that is not the canonical placement below is `TYPE`. Uncovered payload bytes must be `0x00`.
11. A bad bool byte or a nonzero high nibble on an odd packed count is `TYPE`. Quant faults are `TYPE`.
12. A standalone buffer that continues past the block is `TRAILING`. A `tensors` field does not apply this step. The following field owns those bytes.

## Dtypes

Codes 1 through 19 are the closed set. Code 0 is rejected. Codes 20 through 4095 are reserved and rejected. Codes 4096 through 32767 are opaque. A code above 32767 is rejected.

| Code | Name | Element | Bytes |
| --- | --- | --- | --- |
| 1 | `f64` | IEEE binary64 | 8 |
| 2 | `f32` | IEEE binary32 | 4 |
| 3 | `f16` | IEEE binary16 | 2 |
| 4 | `bf16` | 1 sign bit, 8 exponent bits, 7 significand bits, exponent bias 127 | 2 |
| 5 | `f8e4m3` | OFP8 E4M3 | 1 |
| 6 | `f8e5m2` | OFP8 E5M2 | 1 |
| 7 | `bool` | Byte 0 or 1. Any other byte is `TYPE` | 1 |
| 8 | `i8` | Two's complement | 1 |
| 9 | `u8` | Unsigned | 1 |
| 10 | `i16` | Two's complement, little-endian | 2 |
| 11 | `u16` | Unsigned, little-endian | 2 |
| 12 | `i32` | Two's complement, little-endian | 4 |
| 13 | `u32` | Unsigned, little-endian | 4 |
| 14 | `i64` | Two's complement, little-endian | 8 |
| 15 | `u64` | Unsigned, little-endian | 8 |
| 16 | `i4` | Packed two's-complement nibbles | ceil(n / 2) |
| 17 | `u4` | Packed unsigned nibbles | ceil(n / 2) |
| 18 | `e2m1` | OCP MX FP4 E2M1, packed nibbles | ceil(n / 2) |
| 19 | `e8m0` | OCP MX E8M0 scale byte | 1 |

`n` is the element count. For a whole-byte dtype, `byte_length` equals `n` times the width in the table. For a packed dtype, `byte_length` equals `ceil(n / 2)`. The low nibble of a byte is the earlier element. The high nibble is the next element. When `n` is odd, the high nibble of the last byte is 0. A nonzero high nibble is `TYPE`. The values 1, 2, 3 are the bytes `21 03`.

`bf16` value 1.0 is the little-endian bits `0x3F80`, the bytes `80 3f`. `f16` value 1.0 is IEEE binary16 `0x3C00`, the bytes `00 3c`.

`f8e4m3` and `f8e5m2` use the bit layout in the OCP 8-bit Floating Point Specification (OFP8). `e2m1` and `e8m0` use the bit layout in the OCP Microscaling Formats (MX) Specification, version 1.0. Kiln stores those bits. A conforming reader may return them without converting them to a wider float. The golden `f8` case records the bytes `38` and `3c` and does not assign them a decimal value.

Code 1 means `f64`. The directory version byte is separate from the dtype code.

## Quantization

Quantization metadata names other tensors. It does not change element bits, and the reader does not apply a scale.

| Scheme | Name | Rule |
| --- | --- | --- |
| 0 | none | `group_size` is 0, `quant_axis` is `0xFFFF`, and both indexes are `0xFFFFFFFF` |
| 1 | scales | One sibling holds the block scales |
| 2 | scales and outer | Scheme 1, plus one outer `f32` tensor with element count 1 |

For scheme 1 or 2 the rank is at least 1, `quant_axis` is less than the rank, and `group_size` is at least 1. The scale index points at a different tensor in this directory. That tensor uses scheme 0. Its element count equals

```text
ceil(shape[axis] / group_size) * product(shape[i] for i != axis)
```

The product of no dimensions is 1. A rank-1 tensor of 32 elements with group size 32 needs one scale. The scale tensor's dtype is not fixed by the scheme. The case `kiln-v2-scales` uses `e2m1` elements and one `e8m0` byte of value 127, which is the MXFP4 block of 32. Kiln checks the count and stores the byte.

Scheme 2 adds `outer_index`, distinct from the data tensor and the scale tensor. The outer tensor is `f32`, scheme 0, and has one element. The case `kiln-v2-scales-outer` is 16 `e2m1` elements, one `f8e4m3` scale byte, and one `f32` outer value. That is the shape of a 16-element block with an 8-bit scale and a tensor-level `f32` scale. The file stores the three tensors. It does not store a tiled scale layout.

A scale tensor does not itself carry a scheme. Chains are `TYPE`.

## Opaque layouts

Dtype codes 4096 through 32767 are opaque. `byte_length` is explicit. The shape product is not checked against an element width. `layout_len` is at least 1, the layout name is UTF-8 in the heap, and `block_size` is at least 1. `byte_length` is a multiple of `block_size`.

The case `kiln-v2-opaque` uses code 4096, the layout name `Q4_K`, block size 18, and 18 payload bytes. The name records a foreign block layout. Kiln does not interpret the block. A missing layout name is `TYPE`.

Whole-byte and packed dtypes have `block_size` 0 and no layout name.

## Canonical layout

Encoders write this layout. Decoders require it. The result is one byte string for one ordered list of tensors.

1. Descriptor order is the order the caller supplied. A dict of tensors is sorted by key before this step, with the same byte order Frozen uses for dict keys. A struct field or an ordered list keeps that order. Tensor names are not sorted again inside the directory.
2. The name heap is the concatenation defined above.
3. Payload offsets are greedy. The running end starts at 0. Each tensor's `byte_offset` is the next multiple of 64 at or after that end. The first offset is 0. The running end then becomes `byte_offset + byte_length`.
4. `payload_bytes` equals the running end after the last tensor, or 0 when there are no tensors. Bytes in the payload region that no tensor covers are `0x00`. Those bytes are the alignment gaps.
5. Header and descriptor reserved bytes are 0. The little-endian flag is set. The name flag is set when any tensor has a name.

A second tensor therefore starts at offset 64 when the first payload is shorter than 64 bytes. `kiln-v2-f8-pair` is that placement: one `f8e4m3` byte, then one `f8e5m2` byte at offset 64. The 63 bytes between them are zero.

## Embedding

A Frozen struct writes its fields in order. When a field has type `tensors`, the writer emits one canonical version-2 block and continues with the next field.

`kiln-v2-in-struct` is `struct{id:i64,batch:tensors,}` with `id` 7 and the `f32` vector from `kiln-v2-f32`. The body is the little-endian `i64` and then that 200-byte block.

`kiln-v2-framed` is the same struct with an empty directory, wrapped in a Frozen frame. The hash is `0xe58aadc7552f0d82`.

`kiln-v2-bad-version` sets the version byte to 1. The reader returns `FRAME`.

## Errors

| Code | When |
| --- | --- |
| `FRAME` | Magic, version, flags, or a reserved byte |
| `LIMIT` | Cap, or a size product that overflows |
| `EOF` | A checked length does not fit in the buffer |
| `TYPE` | Dtype, shape, range, name, quant, or canonical-layout fault |
| `UTF8` | A name or a layout name |
| `TRAILING` | A standalone buffer continues past the value |
| `SCHEMA` | A frame hash does not match the destination type |

`SCHEMA` is the frame error for a hash that does not match the destination type.

## Golden cases

Forty-six cases are in `spec/kiln-v2-cases.json`. Each case has the hex, the expected accept or reject, and the error code when it rejects. Regenerate them with:

```bash
python3 spec/reference/gen_v2_cases.py
```

The script refuses to write the file if a case does not fail at the error recorded here. `tests/test_tensor_v2.mojo` checks the same rules in the Mojo library.

| Case | Result | What it pins |
| --- | --- | --- |
| `kiln-v2-empty` | accept | Header-only directory |
| `kiln-v2-f32` | accept | `f32` bits, one descriptor, endian |
| `kiln-v2-f32-scalar` | accept | Rank 0 |
| `kiln-v2-f32-negzero` | accept | Sign of zero |
| `kiln-v2-f64-nan` | accept | NaN payload bits |
| `kiln-v2-f16-named` | accept | Name heap and zero pad |
| `kiln-v2-bf16` | accept | `bf16` 1.0 |
| `kiln-v2-i8` | accept | Two's complement |
| `kiln-v2-bool` | accept | One byte per bool |
| `kiln-v2-u4` | accept | Low nibble first |
| `kiln-v2-f8-pair` | accept | Both f8 codes and offset 64 |
| `kiln-v2-scales` | accept | Scheme 1, MXFP4-shaped block |
| `kiln-v2-scales-outer` | accept | Scheme 2, outer `f32` |
| `kiln-v2-opaque` | accept | Layout name `Q4_K` |
| `kiln-v2-in-struct` | accept | Directory after an `i64` |
| `kiln-v2-framed` | accept | Hash of the `tensors` token |
| `kiln-pod-list-f32` | accept | List of `f32` that fits |
| `kiln-v2-bad-magic` | `FRAME` | Magic |
| `kiln-v2-bad-version` | `FRAME` | Directory version other than 2 |
| `kiln-v2-empty-name-flag` | `TYPE` | Name flag on an empty directory |
| `kiln-v2-le-clear` | `FRAME` | Little-endian flag |
| `kiln-v2-unknown-flag` | `FRAME` | Unknown flag |
| `kiln-v2-reserved` | `FRAME` | Reserved header byte |
| `kiln-v2-directory-eof` | `EOF` | Count whose directory does not fit |
| `kiln-v2-count-cap` | `LIMIT` | Count 16,777,217 at the default cap |
| `kiln-v2-directory-mismatch` | `TYPE` | `directory_bytes` |
| `kiln-v2-shape-overflow` | `LIMIT` | Shape product |
| `kiln-v2-length-mismatch` | `TYPE` | Width times count |
| `kiln-v2-overlap` | `TYPE` | Overlapping ranges |
| `kiln-v2-unaligned` | `TYPE` | Canonical offset |
| `kiln-v2-nonzero-pad` | `TYPE` | Zero padding |
| `kiln-v2-duplicate-name` | `TYPE` | Unique names |
| `kiln-v2-bad-utf8` | `UTF8` | Name bytes |
| `kiln-v2-bool-byte` | `TYPE` | Bool byte 2 |
| `kiln-v2-scale-count` | `TYPE` | One scale per group |
| `kiln-v2-opaque-no-layout` | `TYPE` | Opaque layout required |
| `kiln-v2-trailing` | `TRAILING` | Standalone length |
| `kiln-v2-high-nibble` | `TYPE` | Odd packed tail |
| `kiln-v2-shape-tail` | `TYPE` | Shape slots past the rank |
| `kiln-v2-dtype-zero` | `TYPE` | Code 0 |
| `kiln-v2-dtype-reserved` | `TYPE` | Code 20 |
| `kiln-v2-payload-overflow` | `LIMIT` | `payload_bytes` near 2^64 |
| `kiln-list-struct-hostile` | `EOF` | Count 16,777,216 and no elements |
| `kiln-list-struct-short` | `EOF` | Two structs, one present |
| `kiln-list-str-short` | `EOF` | Three strings, one length present |
| `kiln-pod-list-short` | `EOF` | Two `f32`, four payload bytes |

## Not in this version

This version does not add a columnar profile, a compression wrapper, or per-field evolution tags. It does not dequantize. It does not define a GPU pointer. A borrowed CPU view of a payload is the interchange a later DLPack export would use. The export itself is an API, not a wire rule.

A directory version other than 2 is rejected. A longer string or list is accepted when the caller raises the library cap.

## Dynamic values

`schema_from_json` reads a JSON Schema subset: `boolean`, `integer` with an optional `format` (`int8` through `int64`, `uint8` through `uint64`), `number` (`float` or the default `double`), `string`, `string` with `"format": "binary"`, `array`, `object`, and `$ref` of the form `#/$defs/Name`. A property listed in `required` is present. A property left out of `required` is `opt<...>`. If `required` is omitted, every property is present. An object whose only value schema is `additionalProperties` is a `Dict[String, V]`.

The generator `gld-kilngen-mojo` emits one Mojo file of structs. Those structs use the same `encode` and `decode` as a hand-written struct. A `tensors` field is not produced from that JSON subset.

## What a trusted reader may skip

`decode` checks bounds, UTF-8, and the tensor-directory rules. `Reader.u8_fast`, `u32_fast`, `u64_fast`, and `str_fast` do not check bounds. They are for a buffer this process just encoded, or another buffer whose length was already checked. A hostile length passed to `str_fast` can read off the end of the span.
