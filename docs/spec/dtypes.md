# Dtypes {#dtypes}

A dtype is the 16-bit code for one element type. The closed set exists so an unknown code is a hard error rather than a private extension that another reader cannot see.

This page is that set. [A numeric array](array.md) explains why the payload is the bits of these codes. Codes 1 through 19 are defined below. Code 0 is rejected. Codes 20 through 4095 are reserved and rejected. Codes 4096 through 32767 are [opaque](opaque.md). A code above 32767 is rejected. A bad bool byte is [`TYPE`](glossary.md#type), case `kiln-v2-bool-byte`. A nonzero high nibble on an odd packed count is `TYPE`, case `kiln-v2-high-nibble`.

Case `kiln-v2-u4` stores the values 1, 2, 3 as the bytes `21 03`. The low nibble of a byte is the earlier element.

## Why the set is closed

The set is closed so that code 2 means `f32` in every implementation, and a reader does not have to negotiate types. A dtype is a 16-bit integer. The payload width is then a fact: four bytes per `f32`, one byte per `e8m0`, half a byte per packed `u4` rounded up. The directory can check `byte_length` against the shape product. An open-ended type name would make that check a plugin.

The alternative is a string type name in the heap, the way some model files name dtypes in JSON. Strings are extensible and slow to compare, and two spellings of the same type become two types. Another alternative is to leave a hole in the integer space and let vendors register codes. Kiln reserves 20 through 4095 and rejects them, so a private code cannot pass as a standard one by accident. The escape hatch is the opaque range, 4096 through 32767, which requires a layout name and a block size. A foreign layout is allowed. A foreign layout pretending to be code 2 is not. Code 0 is rejected so an uninitialized descriptor fails.

Kiln stores the bits and, for the 8-bit and 4-bit floats, does not require the reader to widen them. Case `kiln-v2-f8-pair` records the bytes `38` and `3c` and assigns no decimal. That is a good decision because widening is a numeric policy, and policies differ at the edges. The wire's job is the bits from the OCP layouts those codes name. Bool is the exception that is not "any byte": a byte other than 0 or 1 is `TYPE`, because a bool that is 2 is not a bool. Packed values put the earlier element in the low nibble, and an odd count must leave the high nibble 0. Case `kiln-v2-u4` is the bytes `21 03` for 1, 2, 3.

The advantage is a table small enough to implement in full, a length check that does not call user code, and a separate door for foreign blocks. The cost is that a new standard float does not appear by writing a new number. It waits for a later version of this table, or it travels as an opaque layout with a name.

Analogy. A paint shop publishes a card of official colors, each with a number. A customer who brings a private mixture does not get to call it color 2. They get a labeled tin in the foreign rack. The official card stays short enough that every clerk knows it. The foreign rack is the opaque range.

| Choice | What it makes cheap | What it makes impossible | What still does that job |
| --- | --- | --- | --- |
| A closed table of codes | Two readers agree on what code 2 means | Inventing code 20 for a private float | An opaque code from 4096 upward, with a layout name |
| Packed nibbles, low nibble first | Two elements share a byte | A packed element that occupies a whole byte | The whole-byte codes, such as `i8` and `u8` |

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
