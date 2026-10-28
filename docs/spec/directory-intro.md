# Names, scales, and foreign blocks

A [directory](glossary.md#directory) is a version-2 block, magic `KLNT`, that holds zero or more tensors and the bytes of their elements. It exists so one value can carry several arrays, each with a dtype and a shape, without treating each element as its own field.

## Why names, scales, and foreign blocks share one block

Names, scales, and foreign blocks share one block because they are three descriptions of numeric bytes, and a directory is already a table of descriptions. A name says which array this is when the struct does not. A scale says how to interpret a quantized block, and it is itself an array. A foreign layout says "these bytes belong to someone else's rule." Giving each its own file format would split one sample into three parsers. Giving each a private side channel would mean three length checks.

The alternative for names is a JSON object whose keys are the tensor names, which is what safetensors does in its header. The names are then obvious to a tool, and the header is a second language. Kiln puts the names in a heap, in descriptor order, and sets a flag only when at least one tensor has a name. An empty directory with the flag set is `TYPE`. Mixed named and unnamed tensors are not representable. That restriction keeps the heap a simple concatenation. If you need a name on one tensor, name them all.

The alternative for a scale is to multiply it in during the read. The caller would receive floats, and the file would no longer be the bits the writer stored. Kiln stores the scale as another tensor and checks that the count matches the groups. The multiplication stays outside. The alternative for a foreign block is to reject it or to teach Kiln the layout. Rejection makes every new block a new file. Teaching Kiln `Q4_K` makes the book a catalog of other projects. An opaque dtype keeps the block in the directory and refuses to interpret it.

This is a good decision when one value must travel as a unit: weights and their scales, or a sample and a mask, or a block this version will never decode. The advantage is one header, one alignment rule, and one check order. The cost is the table in front of small payloads, the ban on a half-named directory, and a `Q4_K` payload that round-trips without being validated as `Q4_K`. The cases below are those choices in bytes. The tables are [Tensor directory](tensor-directory.md).

Analogy. One crate holds the goods, a card naming each compartment, a legend for the coded labels, and a sealed tin the shop does not open. Three crates would need three bills of lading. The card, the legend, and the tin are the name, the scale, and the opaque block.

This chapter answers what an empty directory, a named tensor, a pair of aligned payloads, a scale, and a foreign block look like in the golden cases. The byte tables are [Tensor directory](tensor-directory.md).

Case `kiln-v2-empty` has no tensors. Every length field is zero, the little-endian flag is set, and the name flag is clear. The block is the 64-byte header, copied from that case:

```text
4b4c4e54020200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
```

Case `kiln-v2-f16-named` stores a name in the heap. The case says the name heap is the single byte `77`, and that the padding from the heap to the payload base is zero. IEEE binary16 1.0 is the bytes `00 3c`. The name flag is set. An empty directory with that flag set is case `kiln-v2-empty-name-flag`, and the error is [`TYPE`](glossary.md#type).

Case `kiln-v2-f8-pair` places two one-byte tensors so the second starts at payload offset 64. The bytes between them are zero. That gap is the alignment rule in [Canonical layout](canonical.md). The case is 385 bytes. Kiln stores the `f8` bytes and does not widen them to a decimal value.

A scale stored beside the samples is another tensor in the same directory. Kiln checks that the number of scale elements matches the groups, and it does not multiply the scale into the samples. Case `kiln-v2-scales` is 32 `e2m1` elements and one `e8m0` byte of value 127. The case is 385 bytes. Case `kiln-v2-scales-outer` is 16 `e2m1` elements, one `f8e4m3` scale byte, and one outer `f32` tensor. The case is 580 bytes. A scale tensor that itself carries a scheme is `TYPE`. The scheme table is [Quantization](quantization.md).

Case `kiln-v2-opaque` is a foreign block. The dtype is 4096, the layout name is `Q4_K`, the block size is 18, and the payload is 18 bytes. Those payload bytes end the case: `00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f 10 11`. Kiln checks the name and that the length is a multiple of the block size. It does not interpret the 18 bytes. A missing layout name is `TYPE`, which is case `kiln-v2-opaque-no-layout`.

| Choice | What it makes cheap | What it makes impossible | What still does that job |
| --- | --- | --- | --- |
| A name heap, and a name flag set only when some tensor has a name | One canonical heap, and an empty directory with the flag clear | A directory that mixes named and unnamed tensors | Names on every tensor, or two separate directories |
| A scale stored as another tensor | The element bits stay unchanged, and the group count is checked | Multiplying the scale in during the read | The caller's arithmetic, after the check |
| Opaque dtype codes 4096 through 32767 | A foreign block rides in the same file | Kiln understanding the `Q4_K` layout | The program named by the layout string |
