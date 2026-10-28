# The same record in three encodings

A record encoding is the way one struct becomes bytes. Kiln specifies that encoding for programs that already share the struct, so the bytes can carry the values without carrying the names.

This chapter answers a direct question. For one struct that JSON, Protocol Buffers, and Kiln can all express, what does each format put in the bytes, and what does Kiln refuse to recover later?

The struct is `Point`, with `x` declared before `y`. Both fields are 32-bit integers. The values are 9 and −4. The file `spec/golden/point.kiln` holds Kiln's bytes: `09 00 00 00 fc ff ff ff`.

JSON's text for the same two numbers is `{"x":9,"y":-4}`, 14 characters. The names are in the text. A Protobuf illustration with `int32` fields 1 and 2 is `08 09 10 fc ff ff ff ff ff ff ff ff 01`, 13 bytes. The negative `int32` is a ten-byte varint. Those Protobuf bytes illustrate another standard. They are not a Kiln encoding.

## Why declaration order is the encoding

Declaration order is the encoding because the struct is already an ordered list, and the compiler walked it when the program was built. Putting the names back on the wire spends bytes to tell the reader a fact it used to compile. Putting field numbers on the wire spends a tag, and buys the right to skip a number. Kiln spends neither, and it does not have that right. For `Point`, the spend is visible. JSON is 14 characters and includes `x` and `y`. The Protobuf `int32` illustration is 13 bytes, and −4 alone is a ten-byte varint because a negative `int32` is widened. Kiln is the eight bytes in `spec/golden/point.kiln`. The eight bytes are the design.

The alternatives are good at jobs Kiln refuses. JSON lets a person open the file and see a new field. Protobuf lets an old service ignore a field a new client added. MessagePack and CBOR keep a map, so a reader written by a different team can still find `label`. FlatBuffers spends an offset per field so the unread part of a buffer can stay untouched. Those designs win when the two programs do not share a release. Kiln wins when they do: a message between two processes built together, a record in a file both tools were generated from, a batch of samples whose layout is the training job's struct.

The advantage is a record that is stores and copies. The decoder does not hunt for a key. The cost is the one to say plainly. A third field added by the writer is not skipped by an old reader. The old reader stops, or, without a frame, it reads off the end or into the next value. [The frame](frame-intro.md) is how the stop happens before the first field. A project that must keep old files readable field by field should stay with Protobuf. A project that must let a stranger read the file in a text editor should stay with JSON. A project that owns both ends should use the eight bytes.

Analogy. A paper form with the label printed in each box is JSON. A stranger can see what the box holds. A form whose boxes are numbered is Protobuf. A clerk with a newer form can skip a number they do not use. Kiln is the layout printed in a handbook both clerks already hold. The envelope contains the values in handbook order and does not repeat the handbook. The handbook is the struct. Losing the handbook means you cannot read the envelope, which is the point of the frame hash rather than a defect hidden in the corner.

| Choice | What it makes cheap | What it makes impossible | What still does that job |
| --- | --- | --- | --- |
| Names in the text, as JSON does | A reader can discover a field it was not built with | A record with no name before each value | JSON |
| Field numbers, as Protobuf does | A reader can skip an unknown field | A record with no tag before each value | Protocol Buffers |
| Declaration order, as Kiln does | The bytes are the values, in an order both programs already know | Skipping a field the reader was not built with | The reader stops. [The frame](frame-intro.md) detects a mismatched type |

The rule the golden file records: two 32-bit integers occupy eight bytes, and the names are not among them. A reader built from the opposite field order would assign 9 and −4 to the wrong fields, unless the frame hash fails first with [`SCHEMA`](glossary.md#error-schema). The hash is specified in [Schema hash](schema-hash.md).

## What Kiln guarantees

Kiln is a [positional](glossary.md#positional) [little-endian](glossary.md#little-endian) encoding for a program that already knows the [schema](glossary.md#schema) and that also moves numeric arrays. Four properties define the format. The sections after this one are the rules that make the properties hold.

**The numeric payload is the array.** A fixed-width number is stored as its little-endian bits. A list of those numbers is those bits in order. A tensor payload is the same kind of region, and each payload begins at an offset that is a multiple of 64 from the start of its directory. The directory is a table of fixed-width records: a dtype code, a rank, a shape, a byte offset, and a byte length. A reader checks the table and then uses the payload in place. A reader that was asked for an owned copy writes the payload once into the caller's buffer, or into a new buffer when the caller asked for one. A quantized block stays bits. Its scale is another tensor in that directory. Kiln does not multiply them.

**The same value has the same bytes, and the schema is not in those bytes.** Fields are written in declaration order, with no name and no tag on the wire. Dict keys are written in lexicographic order of their UTF-8 bytes. Frozen inserts no padding. A floating-point value keeps every bit, including the payload of a NaN and the sign of zero. A tensor directory has one canonical layout, defined below, so two encoders of the same tensors write the same block. A frame may carry an FNV-1a 64-bit hash of the canonical type text. If the hash does not match the type the reader was given, the reader stops before the first field.

**A record and its arrays are one buffer.** The tensor directory is a Frozen value. Its canonical name is `tensors`. A struct field of that type is the directory block, and the next field begins at the end of the block. One message can hold an identifier, a string, and the arrays. The identifier and the string are stores and a length. The arrays are the directory and the payloads.

**A count cannot allocate past the bytes that remain.** The reader of a list, a dict, or a tensor directory computes how many bytes the claimed count requires at minimum. If that product overflows, or if it is larger than the unread portion of the buffer, the reader returns an error and does not allocate element storage. The check uses the schema, so it does not need to parse the elements first. A separate trusted reader may skip UTF-8 checking and the quant-shape arithmetic for a buffer this process has just written. It still rejects a length that would read past that buffer.

These four properties are the advantage over the formats that already solve one of these jobs. Safetensors puts raw arrays after a header, and that header is JSON, so a struct, a canonical record encoding, and the allocation rule are outside its job. Protobuf describes a struct by tagging and parsing each value. FlatBuffers and Cap'n Proto borrow fields by storing an offset with each field. GGUF carries quantized weights as a model file, with a sequential metadata preamble and ggml's block layouts. Kiln leaves the schema in the program, puts one hash in the frame, puts a length only on a value that has a length, and leaves the numeric payload as the array itself.

Schema evolution and columnar table scans stay outside this version. A changed struct fails the frame hash. A list of fixed-width numbers is already one contiguous column.

The phrase "defined below" in the second property points at [Canonical layout](canonical.md). The four properties themselves are unchanged from the single-page specification.
