# Canonical layout {#canonical-layout}

The canonical layout is the one placement of descriptors, names, and payloads that encoders must write and decoders must require. One placement exists so two encoders of the same tensors produce one byte string.

Case `kiln-v2-f8-pair` is the alignment example: one `f8e4m3` byte, then one `f8e5m2` byte at payload offset 64, with 63 zero bytes between them. An offset that is not this placement is [`TYPE`](glossary.md#type), case `kiln-v2-unaligned`. A nonzero pad byte is `TYPE`, case `kiln-v2-nonzero-pad`. Overlapping ranges are `TYPE`, case `kiln-v2-overlap`.

## Why one placement exists

One placement exists so that "the same value has the same bytes" is true of a directory, not only of a struct. Two encoders that may put payloads at any non-overlapping offset will write two files for one list of tensors. A hash of the file, a cache, and a test will then disagree. Kiln picks the placement and requires decoders to reject any other.

The alternative is to accept any non-overlapping layout and treat the descriptor offsets as authoritative. That is easier to write, and it makes the bytes depend on the encoder's whim. Another alternative is to sort tensors by name before placing them. Sorting would make a dict of tensors canonical even if the caller built it in a random order. Kiln already sorts dict keys before it builds the directory. Inside the directory, caller order is kept, because a struct field and an ordered list have an order that sorting would destroy. A third alternative is to omit the zero gaps and pack payloads tight. Tight packing saves the 63 bytes between two 1-byte tensors. It also puts the second payload at an address the 64-byte rule was invented to avoid.

The procedure is short. Descriptors stay in caller order. The name heap is the names, then the layout names, with no holes. Offsets are greedy: the running end starts at 0, each payload starts at the next multiple of 64, and `payload_bytes` is the end after the last tensor. Uncovered bytes are `0x00`. Case `kiln-v2-f8-pair` is the picture: one byte, then 63 zeros, then the second byte at offset 64. Case `kiln-v2-unaligned` is a legal-looking block in the wrong place, and the error is `TYPE`. Case `kiln-v2-nonzero-pad` hides a nonzero byte in a gap. Case `kiln-v2-overlap` reuses a range.

This is a good decision for interchange. A test can compare buffers. A cache can key on bytes. A decoder can refuse a "helpful" writer that packed tight. The cost is the alignment gap, which is large relative to a one-byte tensor and small relative to a weight matrix. The cost is also rigidity: a block that is only slightly rearranged is not Kiln until it is rewritten into this order.

Analogy. A choir stands in an assigned order so two recordings of the same singers match. A choir that may stand anywhere will still sing the right notes and will not produce the same recording. The assigned order is the canonical layout. The recording is the byte string.

| Choice | What it makes cheap | What it makes impossible | What still does that job |
| --- | --- | --- | --- |
| Caller order of descriptors, then greedy 64-byte offsets | Equality of two buffers is equality of the tensors | A decoder that accepts any non-overlapping placement | A tool that rewrites a block into this order before it is called Kiln |
| Uncovered payload bytes must be `0x00` | The gaps are determined | Hiding extra data in an alignment gap | A separate field in the enclosing struct |

Encoders write this layout. Decoders require it. The result is one byte string for one ordered list of tensors.

1. Descriptor order is the order the caller supplied. A dict of tensors is sorted by key before this step, with the same byte order Frozen uses for dict keys. A struct field or an ordered list keeps that order. Tensor names are not sorted again inside the directory.
2. The name heap is the concatenation defined in [Names](tensor-directory.md#names).
3. Payload offsets are greedy. The running end starts at 0. Each tensor's `byte_offset` is the next multiple of 64 at or after that end. The first offset is 0. The running end then becomes `byte_offset + byte_length`.
4. `payload_bytes` equals the running end after the last tensor, or 0 when there are no tensors. Bytes in the payload region that no tensor covers are `0x00`. Those bytes are the alignment gaps.
5. Header and descriptor reserved bytes are 0. The little-endian flag is set. The name flag is set when any tensor has a name.

A second tensor therefore starts at offset 64 when the first payload is shorter than 64 bytes. `kiln-v2-f8-pair` is that placement: one `f8e4m3` byte, then one `f8e5m2` byte at offset 64. The 63 bytes between them are zero.
