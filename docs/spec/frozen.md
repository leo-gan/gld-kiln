# Frozen values {#frozen-values}

A Frozen value is one Kiln value written in [declaration order](schema.md), with no names and no padding. Frozen is profile 0, and it is the default because the other profile codes are not the layout this version asks encoders to write.

This page answers how each scalar, string, list, optional, dict, and struct is laid out, including the `tensors` value. The worked integers are `spec/golden/point.kiln`: `09 00 00 00 fc ff ff ff`.

A directory version other than 2 is [`FRAME`](glossary.md#error-frame). A standalone buffer that continues past the value is [`TRAILING`](glossary.md#trailing). Nesting deeper than 64 containers is a depth error.

## Why Frozen exists

Frozen exists because both programs were built from the same struct, and a name or a tag in front of every value repeats that fact. The repetition is not free. It costs bytes, and it costs a branch while the reader decides what the next field is. On one record the branch is small. On a batch it is paid once per field per record. Frozen removes it by writing the values in declaration order and nothing else between them.

The alternatives are the formats that keep the description in the bytes. JSON writes the name. Protobuf writes a field number and a wire type, which is what lets a reader skip a field it does not know. MessagePack and CBOR write a type tag and, for a map, the name. FlatBuffers writes an offset so a field can be absent and the rest of the buffer can stay unmoved. Each of those is a good design for a reader that does not have the writer's source. Kiln is for the reader that does. Creating a second copy of the schema on the wire would spend the budget those other formats spend on compatibility, on a path where compatibility was already settled at compile time.

The no-padding rule is the same decision at the scale of one field. Padding would make a struct land on a 64-byte boundary, which is attractive for a numeric payload and useless for two integers. `spec/golden/point.kiln` is eight bytes. Padding it to 64 would make the file larger and would not remove a store. The 64-byte boundary is reserved for tensor payloads, where the numeric bytes are large enough for the alignment to matter. A struct that contains a directory still has no padding around the directory. The directory brings its own alignment, and the next field starts at the end of the block.

This is a good decision when the struct is the contract. The encoder is a sequence of stores. The decoder is a sequence of loads. Dict keys are sorted so a mapping, which has no declaration order, still has one byte string. The cost is the one Frozen accepts on purpose. An old reader cannot skip a field a new writer added, because there is no tag to skip. The frame hash fails the buffer instead. A program that must serve old and new structs at once should use Protobuf, or it should keep both structs and convert outside this layout.

Analogy. A concert ticket can be printed as three numbers in a published order: row, seat, price. The words "row" and "seat" are on the hall's diagram, not on every ticket. Two clerks with the diagram read the ticket. A stranger without the diagram cannot. Frozen is that ticket. The diagram is the struct.

| Choice | What it makes cheap | What it makes impossible | What still does that job |
| --- | --- | --- | --- |
| No padding between fields | The size of a struct is the sum of its fields | Aligning a small struct to 64 bytes inside Frozen | A tensor payload is aligned inside its directory, not inside the struct |
| `tensors` as one Frozen value | The next field starts at the end of the directory block | A second framing around the directory | [Embedding](embedding.md) |

The scalar, string, list, optional, and dict encodings follow the minimum-size table on [Lengths and allocation](lengths.md), including sorted dict keys and the rule that Frozen inserts no padding.

One type is added.

| Canonical name | Encoding |
| --- | --- |
| `tensors` | One complete version-2 tensor directory, including its magic. The block length is determined by the header. The next field starts at the end of the block. |

A `tensors` value is a version-2 directory. Any other directory version is `FRAME`.

`decode` of a standalone value still requires the buffer to contain exactly that value. Nesting deeper than 64 containers is still a depth error.
