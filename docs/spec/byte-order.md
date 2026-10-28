# Byte order {#byte-order}

Little-endian order stores the least significant byte of a multi-byte number first. Kiln uses that one order on every machine so two encoders of the same number write the same bytes.

This page answers which bit patterns are required, and what the little-endian flag does and does not select. The reason for a fixed order is [Widths, lengths, and byte order](widths.md).

Case `kiln-v2-f32` records `f32` 1.0 as `00 00 80 3f`. Case `kiln-v2-f32-negzero` records −0.0 as `00 00 00 80`. Case `kiln-v2-f64-nan` records the quiet NaN with payload 1 as the bits `0x7FF8000000000001`. Case `kiln-v2-le-clear` clears flag bit 1 and the error is [`FRAME`](glossary.md#error-frame).

## Why one byte order exists

A multi-byte number is more than one memory cell, and the cells have an order. If the writer and the reader disagree about the order, the number 1 becomes a very different bit pattern. Kiln picks little-endian for every multi-byte integer and every multi-byte floating-point value, on every machine, so two encoders of the same value write the same bytes. The patterns are part of the rule: `f32` 1.0 is `00 00 80 3f`, negative zero is `00 00 00 80`, and the quiet NaN with payload 1 keeps the bits `0x7FF8000000000001`. Numeric equality would hide the last two. The wire does not.

The alternative is the host's own order, or a flag that selects an order. Host order is the natural thing for a little-endian CPU, and it is a different format on a big-endian CPU. A selecting flag looks flexible. It also means one value has two legal byte strings, so "the same value has the same bytes" stops being true, and every reader grows a branch. Kiln's flag bit 1 must be set, and a clear bit is `FRAME`, case `kiln-v2-le-clear`. The bit records that the payloads follow this page. It does not choose.

Kiln allows a little-endian host to copy memory when the host type has the same width and order as the wire type. That permission is the performance argument, and it is fenced. On any other host the implementation byte-swaps, or it refuses before it writes. A refusal is conforming. Writing host order and calling the result Kiln is not. Single-byte dtypes and packed nibbles may be copied on any host, because a byte has no order. The first element of a packed stream is still the low nibble. That is an order of elements inside a byte, and it is fixed too.

This is a good decision because canonical bytes are worth more, in this format, than saving a swap on a rare host. The common host already matches. The uncommon host pays a swap or a refusal, which is visible, instead of silently producing a file other readers will misread. The cost is that a big-endian program cannot treat Kiln as a dump of its registers.

Analogy. Two people can write a date as day then month, or as month then day. A contract that will be read in more than one country publishes one order. Kiln publishes little-endian the way that contract would publish day then month. A note in the margin that says "we did use that order" is the flag. The note is not permission to use the other order.

| Choice | What it makes cheap | What it makes impossible | What still does that job |
| --- | --- | --- | --- |
| One byte order for every host | A little-endian machine can store the bits it already uses, when the width matches | Writing a big-endian host's native order and calling it Kiln | A byte swap, or a refusal before the write. A refusal is conforming |
| A flag that must be set, and that does not choose an order | A reader can reject a block that never claimed this byte order | Using the flag as a switch between two orders | There is no second order in this version |

Multi-byte integers in Frozen and in both tensor headers are little-endian. IEEE `f16`, `f32`, and `f64`, and `bfloat16`, are little-endian. `f32` value 1.0 is the bytes `00 00 80 3f`. `f32` negative zero is `00 00 00 80`. The `f64` quiet NaN with payload 1 used in the golden cases is the bits `0x7FF8000000000001`, little-endian.

Single-byte dtypes, and the bytes of a packed nibble stream, may be copied on any host. A packed stream is still a sequence of bytes in wire order. The first element is the low nibble of the first byte.

The tensor directory sets flag bit 1, the little-endian bit. A reader rejects the block when that bit is clear. The bit does not select a byte order. It records that the payloads follow this section.
