# Check order {#check-order}

The check order is the sequence of tests a directory reader applies, and the first failure is the error a golden case records. A fixed order exists so two decoders report the same code when a block has more than one fault.

This page answers which fault wins. The cases in [Golden cases](golden.md) are written against this sequence. A wrong magic is [`FRAME`](glossary.md#error-frame) at step 1, before a short buffer is treated as [`EOF`](glossary.md#eof). A count above the cap is [`LIMIT`](glossary.md#limit) at step 3, before the reader asks whether the directory fits.

## Why the order is fixed

The order is fixed because a damaged block usually has more than one fault, and two decoders that report different faults cannot share a test. Kiln publishes the sequence and requires the first failure. A later fault in the same block is not what the golden case records.

The alternative is to collect every fault and return a list. That is a better diagnostic for a human repairing a file, and it is a worse oracle for a conformance test. Another alternative is to parse optimistically and return the first fault the programmer happened to code. That order changes when the code is rearranged, and the case file silently starts expecting a different code. A third alternative is to allocate the descriptor array up front and then discover the buffer was short. That turns a truncated header into a large allocation, which is the failure [Lengths and allocation](lengths.md) exists to prevent.

Kiln puts magic and version first, so a wrong file fails as `FRAME` before anyone treats a short buffer as `EOF`. It puts the cap before the fit check, so 16,777,217 tensors is `LIMIT` even when the arithmetic would also overflow the buffer. It checks that `directory_bytes` equals `tensor_count * 128 + name_bytes` before it believes either number. It checks that the block fits before it looks at padding, names, ranges, and quantization. Step 12, `TRAILING`, applies to a standalone buffer and not to a `tensors` field, because the next field owns the bytes after the block.

This is a good decision for a specification that has forty-six cases. Each reject case can name one code, and an implementation that reports a different code is wrong even if it also noticed a second fault. The cost is that a tool which wants every fault must keep walking after the specified failure, on its own, and must not call that walk the Kiln result.

Analogy. A customs desk stops at the first missing stamp and writes that reason down. Two officers then give the same answer. A desk that lists every missing stamp is more informative and will not match the other desk's form. The golden cases are the form.

| Choice | What it makes cheap | What it makes impossible | What still does that job |
| --- | --- | --- | --- |
| The first error in this list is the result | Case files and libraries can share one expected code | Reporting every fault in a corrupted block | A diagnostic tool outside the decoder |
| Allocation only after the count and the block are known to fit | A hostile `tensor_count` does not allocate one descriptor per claim | Decoding a truncated block into a shorter directory | `EOF`, with no descriptor array allocated |


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
10. An offset that is not the canonical placement in [Canonical layout](canonical.md) is `TYPE`. Uncovered payload bytes must be `0x00`.
11. A bad bool byte or a nonzero high nibble on an odd packed count is `TYPE`. Quant faults are `TYPE`.
12. A standalone buffer that continues past the block is `TRAILING`. A `tensors` field does not apply this step. The following field owns those bytes.
