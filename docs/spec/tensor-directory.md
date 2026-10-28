# Tensor directory {#tensor-directory}

A tensor directory is the version-2 block that holds zero or more tensors. Magic `KLNT` and version byte 2 are what a reader checks first, so a different block is not mistaken for this one.

[Names, scales, and foreign blocks](directory-intro.md) walks the golden cases. This page is the layout those cases are checked against. Case `kiln-v2-empty` is the 64-byte header with every length zero. Any other version is [`FRAME`](glossary.md#error-frame). There is no earlier tensor layout.

## Why a directory exists

A directory exists because a numeric array is not a list of fields, and a single count is not enough once the value holds a shape, a name, or a second array. Walking each float as its own Frozen field would add a loop and a store per element. A bare list of floats is already the right encoding when the caller remembers the shape. The directory is the encoding when the shape has to travel with the bits, and when more than one array shares the buffer.

The alternative used by safetensors is a JSON header and then the raw arrays. The header is easy for a tool that does not have Kiln. It is a second parser, it is not a struct, and it does not include Kiln's rule that a count must fit before allocation. Protobuf can store a tensor as a bytes field plus separate integer fields for the dimensions. The reader still parses tags, then parses the blob. FlatBuffers can store a vector of floats behind an offset. The offset is a per-field pointer. GGUF stores quantized weights behind a sequential metadata preamble and interprets ggml block layouts. Kiln's directory is a fixed-width table, then payloads aligned to 64 bytes. The reader checks the table and uses the payload in place, or copies it once if the caller asked for an owned copy.

Kiln fixes the header at 64 bytes and each descriptor at 128 so the arithmetic `tensor_count * 128 + name_bytes` can be checked against `directory_bytes` without trusting either number alone. A mismatch is `TYPE`. Magic `KLNT` and version 2 reject a different block as `FRAME`. There is no version 1. The 64-byte payload alignment is the other half of the decision. Frozen records stay unpadded, because a 44-byte message should not become 64. A payload is where a later reader may load numbers directly, so the start of the numbers is a known boundary. The gaps are zeros. A nonzero gap would be a place to hide bytes, so it is `TYPE`.

This is a good decision for a record that is an identifier plus arrays, which is the shape of a training sample and of an inference request. The description is fixed-width, the bits stay the bits, and a hostile count fails before a descriptor array is allocated. The cost is real on a tiny vector. Case `kiln-v2-f32` is 200 bytes for two floats: 64 of header, 128 of descriptor, and 8 of payload. A Frozen list of those same two floats, case `kiln-pod-list-f32`, is 12 bytes. Use the list when the shape lives in the struct. Use the directory when the shape, the name, or a sibling tensor must live in the value.

Analogy. A crate has a packing list nailed to the lid and the goods set on the slats at regular marks. You read the list, you check that the marks fall inside the crate, and then you lift the goods without unpacking them into envelopes. The packing list is the descriptor. The goods are the payload. The slat spacing is the 64-byte alignment.

| Choice | What it makes cheap | What it makes impossible | What still does that job |
| --- | --- | --- | --- |
| A 64-byte header and a 128-byte descriptor | The reader can check counts against stored lengths | A directory smaller than that table when it holds one short vector | A Frozen list of numbers, which has no descriptor |
| `directory_bytes` equal to `tensor_count * 128 + name_bytes` | Neither the count nor the length is trusted alone | Accepting a header whose arithmetic does not match | The mismatch is [`TYPE`](glossary.md#type) |

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
