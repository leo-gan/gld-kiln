# A numeric array

A numeric array in Kiln is a sequence of fixed-width elements stored as their bits, in order. A list of those elements is a count and then the bits. A [tensor](glossary.md#tensor) is that same kind of region, named by a [dtype](glossary.md#dtype), a [rank](glossary.md#rank), and a [shape](glossary.md#shape), and stored in a [directory](glossary.md#directory).

This chapter answers when the list is the right value, and when the directory is required.

Case `kiln-pod-list-f32` is the list. The bytes `02 00 00 00 00 00 80 3f 00 00 00 c0` are the count 2 and the 32-bit values 1.0 and −2.0. The reader checks that two times four bytes remain, and the payload is the array.

## Why the bits stay the bits

The bits stay the bits because a number in memory is already the value, and a format that wraps each number adds a tax the arithmetic does not need. A list of `f32` is a count and then the IEEE bits in order. Case `kiln-pod-list-f32` is twelve bytes for 1.0 and −2.0. The reader checks that two times four bytes remain, then the payload is the array. No per-element tag, no decimal text, no conversion unless the host byte order differs from the wire.

The alternative is JSON's array of numbers, which is text and a parser. It is the right form for a person. It is a poor form for a million floats. Protobuf's packed repeated float is closer: a length and then the bits, inside a tagged field. Kiln's list is that payload without the surrounding tag, because the struct already said the field was a list of floats. The directory is the step up, not a replacement. Case `kiln-v2-f32` is the same two floats in 200 bytes, because a 64-byte header and a 128-byte descriptor carry the shape. Pay the 200 bytes when the next reader must learn the shape from the value. Pay the 12 bytes when the shape is the struct.

A third alternative is to dequantize or widen on read, so the caller always sees `f32`. That hides `f16`, `bf16`, and the 8-bit floats behind a policy. Kiln stores those codes as their bits. Widening is the caller's choice, made where the rounding can be seen.

This is a good decision for activations, embeddings, and a batch of features. The copy is one copy. A borrowed read is no copy, as long as the buffer outlives the view. The cost is alignment and a table when you step up to a directory, and the absence of a converter. A program that wants decimals in a notebook should print them. The file should keep the bits.

Analogy. A strip of film is the frames in order. You do not write a caption on every frame when the reel already has a label. The list is the strip with a length at the start. The directory is the reel's label, nailed on so the strip can be held up to the light without being cut into envelopes.

The directory is the value that carries a shape beside the bits, or that carries more than one region. Case `kiln-v2-f32` is one unnamed `f32` vector of length 2. The block is 200 bytes: a 64-byte header, one 128-byte descriptor, and 8 payload bytes. The payload is `00 00 80 3f 00 00 00 c0`, the same two values as the list. The shape lives in the descriptor, so the next reader does not have to remember it out of band. The hex is case `kiln-v2-f32` in `spec/kiln-v2-cases.json`.

The rule: a fixed-width number is stored as its [little-endian](glossary.md#little-endian) bits, and a list of those numbers is those bits in order. A tensor [payload](glossary.md#payload) is that kind of region. Each payload begins at an offset that is a multiple of 64 from the start of its directory. A reader checks the directory and then uses the payload in place. A reader that was asked for an [owned copy](glossary.md#owned-copy) writes the payload once. The tables are [Tensor directory](tensor-directory.md) and [Dtypes](dtypes.md).

| Choice | What it makes cheap | What it makes impossible | What still does that job |
| --- | --- | --- | --- |
| Bits in order after one count | A numeric list is one copy | Storing a shape, a name, and a second array in that same value | The directory |
| A payload aligned to 64 bytes | The numeric bytes can be used in place after the table is checked | A header as small as the list's four-byte count, on a two-element vector | The Frozen list. In `kiln-pod-list-f32` the payload starts at byte 4 |
