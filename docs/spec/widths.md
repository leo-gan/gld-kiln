# Widths, lengths, and byte order

A width is the number of bytes a numeric type always occupies. A length is a count written in front of a value whose size the schema does not fix. Kiln uses a width for integers and floating-point numbers, and a length for strings and lists, because only the second group can grow from value to value.

This chapter answers why a number has no size prefix, and why every multi-byte number is [little-endian](glossary.md#little-endian) on every machine.

`spec/golden/point.kiln` is two widths and no length prefix: `09 00 00 00` for 9, then `fc ff ff ff` for −4. Case `kiln-v2-f32` states the same rule for a 32-bit float. The value 1.0 is the bytes `00 00 80 3f`. Case `kiln-v2-f32-negzero` states that −0.0 is `00 00 00 80`, so the sign bit is part of the value. Case `kiln-v2-f64-nan` states that the quiet NaN with payload 1 is the little-endian bits `0x7FF8000000000001`. Numeric equality would treat −0.0 as 0.0 and would not promise to keep a NaN payload. The byte string keeps both.

## Why a number has a width and a string has a length

A number has a width because the type names the size. An `Int32` is four bytes in the source and four bytes on the wire. A prefix would tell the reader something the schema already said, and it would add a branch to every integer in a batch. A string has a length because the type says "text" and the value decides how much text. `hi` in `spec/golden/message.kiln` is `02 00 00 00 68 69`. `z` is `01 00 00 00 7a`. The count is the part the schema could not know.

The alternative for integers is a varint, which is what Protobuf uses. A small positive integer occupies one byte. A negative `int32` occupies ten, as the illustration on [the record page](record.md) shows for −4. Varints win on size for small positives and lose the fixed store. Kiln keeps the fixed store. The alternative for strings is a terminator byte, as C strings use. A terminator cannot hold a byte that equals the terminator, or it must escape it. A `u32` length can hold any bytes, and it can be checked against the buffer before the copy. The alternative for byte order is discussed on [Byte order](byte-order.md): one order, little-endian, including the sign of zero and the payload of a NaN, because those bits are part of "the same value."

This is a good decision for records that are mostly machine numbers and short strings. The integer path is a load or a store of a known size. The string path pays a length check, which is the check that stops a claimed million-byte string from being allocated out of a short buffer. The cost is size on tiny integers. The value 1 occupies four bytes as an `i32`, not one. A format whose messages are dominated by small integers and that must shrink them should use varints. Kiln's measured messages are not that shape, and a branch per integer would be paid again on every record of a batch.

Analogy. A ruler has marks at a fixed spacing, so a length that is always four marks needs no separate note. A piece of string does not have a fixed spacing. You write down how long it is, and then you cut. The note is the `u32`. The cut is the copy. You do not start the cut until the note fits on the table.

Every multi-byte integer and every multi-byte numeric payload is little-endian on every host. Copying host memory into the wire image is conforming only when the host is little-endian and the host type has the same width and order as the wire type. On any other host the implementation byte-swaps, or it refuses the operation before it writes. A refusal is conforming. Writing the host's own byte order and calling the result Kiln is not. The flag that records the choice, and [`FRAME`](glossary.md#error-frame) when that flag is clear, are specified in [Byte order](byte-order.md). Case `kiln-v2-le-clear` is the clear flag.

| Choice | What it makes cheap | What it makes impossible | What still does that job |
| --- | --- | --- | --- |
| Fixed width, little-endian | A number is a store of a known size, with one byte order on every machine | A shorter encoding of a small integer | Protobuf varints |
| A `u32` length on a string | The reader knows how many bytes to take | A string whose length claims more bytes than remain | The reader returns [`EOF`](glossary.md#eof) and does not allocate the body. [Lengths and allocation](lengths.md) states the check |

The precise rule: a fixed-width number is its little-endian bits, and a string is a `u32` length followed by that many bytes.
