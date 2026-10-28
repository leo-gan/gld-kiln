# Embedding {#embedding}

Embedding is writing a tensor directory as one Frozen field, then continuing with the next field. The directory is a value, so a struct can hold an identifier and the arrays in one buffer.

Case `kiln-v2-in-struct` is `struct{id:i64,batch:tensors,}` with `id` 7 and the `f32` vector from `kiln-v2-f32`. The body begins `07 00 00 00 00 00 00 00` and then the 200-byte block. The case is 208 bytes. Case `kiln-v2-bad-version` sets that directory's version byte to 1, and the error is [`FRAME`](glossary.md#error-frame).

## Why the directory is a field

The directory is a field so that an identifier, a string, and the arrays are one buffer. A training sample is that shape. An inference request is that shape: a request id, a model name, a temperature, and the prompt tensors. Two files, one for the struct and one for the arrays, can fall out of step. One file cannot.

The alternative is a sidecar. The struct points at a filename or an offset in another stream. Sidecars are how a lot of training data is stored, and they require a second open and a rule for what happens when the second file is missing. Another alternative is to flatten every tensor into fields of the struct: `rows`, `cols`, and a `list<f32>`. That is the right encoding for one matrix whose shape is part of the struct, and it is awkward for a value that holds a changing set of named arrays. A third alternative is to make the directory its own file format with a footer of offsets. Kiln does not define a footer. The header already says how long the block is, so the next field knows where to start.

Case `kiln-v2-in-struct` is `struct{id:i64,batch:tensors,}` with id 7 and the 200-byte `f32` vector from `kiln-v2-f32`. The body is eight bytes, `07 00 00 00 00 00 00 00`, and then that block. The case is 208 bytes. The standalone rule `TRAILING` does not fire on the bytes after the directory, because those bytes would be the next field. A directory version of 1 inside the field is still `FRAME`, case `kiln-v2-bad-version`. The field does not get a weaker header.

This is a good decision because the record and the arrays stay one checkable value. A reader that knows the struct reads the integer, then runs the directory checks, then reads whatever field follows. The cost is that a generator from the JSON Schema subset does not emit this field. The directory is built with the tensor API and placed in the struct by hand. The cost is also the 192 bytes of table in front of a short vector, which is the same cost the directory has on its own.

Analogy. A letter has a photograph taped to the page. The next sentence starts where the photograph ends. You do not put the photograph in a second envelope and hope the letter and the photograph stay together. The photograph is the directory. The sentence after it is the next field.

| Choice | What it makes cheap | What it makes impossible | What still does that job |
| --- | --- | --- | --- |
| The next field starts at the end of the block | One message holds the identifier, the strings, and the arrays | A standalone trailing-byte check on a directory that is a field | [`TRAILING`](glossary.md#trailing) applies to a standalone directory. The following field owns the bytes after the block |
| The caller's field order | The directory sits where the struct declares it | Sorting tensors by name inside the block | [Canonical layout](canonical.md) keeps caller order |

A Frozen struct writes its fields in order. When a field has type `tensors`, the writer emits one canonical version-2 block and continues with the next field.

`kiln-v2-in-struct` is `struct{id:i64,batch:tensors,}` with `id` 7 and the `f32` vector from `kiln-v2-f32`. The body is the little-endian `i64` and then that 200-byte block.

`kiln-v2-framed` is the same struct with an empty directory, wrapped in a Frozen frame. The hash is `0xe58aadc7552f0d82`.

`kiln-v2-bad-version` sets the version byte to 1. The reader returns `FRAME`.
