# Opaque layouts {#opaque-layouts}

An opaque layout is a dtype code from 4096 through 32767 whose bytes Kiln stores and does not interpret. The code exists so a foreign block can occupy a payload without being mistaken for one of the closed dtype codes.

Case `kiln-v2-opaque` uses code 4096, the layout name `Q4_K`, block size 18, and 18 payload bytes ending `00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f 10 11`. A missing layout name is [`TYPE`](glossary.md#type), case `kiln-v2-opaque-no-layout`.

## Why opaque codes exist

Opaque codes exist because real weight files already use block layouts Kiln does not, and will not, interpret. Rejecting every unknown dtype would make those files a second format beside Kiln. Accepting them as if they were `f32` would make a lie. The range 4096 through 32767 is a dtype that stores bytes, requires a name, and requires a block size, and then stops.

The alternative is a plugin API: the reader calls registered code to validate `Q4_K`. Plugins make a format open and make conformance untestable, because the correct bytes depend on who registered what. Another alternative is to document `Q4_K` inside this book and check its 18-byte structure. That would be one layout, done well, and the next foreign layout would ask for the same treatment until the book became a catalog of other projects. Kiln checks what it can check without knowing the layout. The name is present and is UTF-8. The block size is at least 1. The payload length is a multiple of the block size. The shape product is not compared to an element width, because there is no element width.

Case `kiln-v2-opaque` is code 4096, the name `Q4_K`, block size 18, and 18 payload bytes ending `00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f 10 11`. Kiln does not claim those bytes are a valid `Q4_K` block. It claims they are 18 bytes with that name. Case `kiln-v2-opaque-no-layout` is the same idea with the name missing, and the error is `TYPE`. Whole-byte and packed dtypes keep `block_size` 0 and no layout name, so an `f32` cannot smuggle a layout string.

This is a good decision because the directory stays one table. A foreign block is a tensor with a wider code, not a side channel. The cost is that "Kiln file" does not mean "Kiln understands every payload." A reader that must evaluate `Q4_K` uses the name to choose its own code. A reader that only round-trips the directory copies the bytes.

Analogy. A sealed cartridge sits in the crate. The clerk checks the label and checks that the weight is a whole number of cartridges. The clerk does not open the cartridge. Opening it is a different profession, and the label says which one.

| Choice | What it makes cheap | What it makes impossible | What still does that job |
| --- | --- | --- | --- |
| An explicit byte length and a block size | The shape product is not pretended to be an element width | Checking that the 18 bytes are a valid `Q4_K` block | The program that knows that layout |
| A UTF-8 layout name in the heap | The name travels with the block | A private numeric code in the reserved range 20 through 4095 | Those codes are rejected |

Dtype codes 4096 through 32767 are opaque. `byte_length` is explicit. The shape product is not checked against an element width. `layout_len` is at least 1, the layout name is UTF-8 in the heap, and `block_size` is at least 1. `byte_length` is a multiple of `block_size`.

The case `kiln-v2-opaque` uses code 4096, the layout name `Q4_K`, block size 18, and 18 payload bytes. The name records a foreign block layout. Kiln does not interpret the block. A missing layout name is `TYPE`.

Whole-byte and packed dtypes have `block_size` 0 and no layout name.
