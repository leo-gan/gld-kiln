# Terminology

This page defines every term the specification relies on. The first sentence of each entry is the definition. The sentences after it say why the term is needed, and what Kiln fixes it to mean. The [glossary](glossary.md) is the short index of the same words. A rule in another chapter overrides an example on this page.

## Serialization

Serialization is turning values into a form that can be stored or sent, so another program can rebuild the same values. The word exists because "saving" and "sending" look like different jobs, and they are the same job at the level of bytes. JSON text is one serialization. A Protobuf message is another. Kiln is another. The [repository README](https://github.com/leo-gan/gld-kiln#readme) introduces the word for a reader who has only heard it.

## Schema

A schema is the description of a value's fields, their types, and their order. Without a schema, a reader has to discover the fields from the bytes, which is what names and tags are for. Kiln keeps the schema in the program that was compiled from the struct. The bytes do not repeat it. [Schema and declaration order](schema.md) is the rule.

## Wire

The wire is the sequence of bytes one program writes and another reads. The name comes from a network cable, and the same sequence is a file on disk. Kiln specifies the wire. It does not specify the socket, the filename, or the call that sends the buffer.

## Positional

A positional encoding writes values in a fixed order and does not write a name or a number in front of each value. The reader already knows which value comes next, because the schema says so. JSON is not positional: the name is in the text. Protobuf is not positional: a field number is in the bytes. Kiln's Frozen layout is positional. [The same record in three encodings](record.md) compares the three.

## Declaration order

Declaration order is the order of fields as they are written in the struct source. Kiln uses that order as the wire order for a struct. The alternative is a tag that lets the fields arrive in any order. Declaration order is cheaper when both programs share the source, and it is the wrong tool when an old reader must skip a field it has never seen.

## Little-endian

Little-endian order stores the least significant byte of a multi-byte number first. The least significant byte is the one that changes when the number goes from 1 to 2. Kiln uses this order for every multi-byte integer and every multi-byte floating-point value, on every machine. A flag records that the payloads follow the rule. The flag does not offer a second order. [Byte order](byte-order.md) pins the patterns, including 1.0, negative zero, and a NaN payload.

## Host byte order

Host byte order is the order the CPU uses for its own loads and stores. On a little-endian machine it matches Kiln. On any other machine, copying memory straight into the buffer would write a different byte string from the one this book specifies. A conforming implementation byte-swaps, or it refuses the write. Calling the host's order "Kiln" is not conforming.

## Width

A width is the number of bytes a numeric type always occupies. An `f32` is four bytes. An `i64` is eight. A width needs no count in front of it, because the schema already knows the size. [Widths, lengths, and byte order](widths.md) separates a width from a length.

## Length

A length is a count written in front of a value whose size the schema does not fix. A string is a `u32` length and then that many bytes. A list is a `u32` count and then that many elements. The length is a claim. [Lengths and allocation](lengths.md) says when the claim is rejected before any element storage is allocated.

## Frozen

Frozen is Kiln's default layout, profile code 0. Fields go in declaration order, dict keys go in lexicographic order of their UTF-8 bytes, and nothing is inserted between fields to pad them. The name means the layout is fixed when the program is built, rather than discovered while reading. [Frozen values](frozen.md) is the encoding.

## Profile

A profile is a small integer in a frame that names which record layout follows. Code 0 is Frozen and is the layout this version asks encoders to write. Codes for evolution and for columns are reserved so those experiments cannot silently reuse Frozen's number. [Profiles](profiles.md) is the table and the reason each code is or is not the default.

## Frame

A frame is a sixteen-byte prefix in front of one Frozen value. The prefix is the magic `KLN0`, profile 0, flags, a reserved byte, and the schema hash. It exists so a reader can reject a different struct before the first field. A frame is optional in the sense that a bare Frozen value is still a Kiln value. It is not a container for several top-level values. [Frame](frame.md) lists the sixteen bytes.

## Schema hash

The schema hash is the FNV-1a 64-bit mix of the canonical type text. FNV-1a is a public hash: start from the offset basis 14695981039346656037, and for each byte multiply by the prime 1099511628211 after mixing that byte in. Kiln mixes each token, then a `0x00` byte. The hash covers the type. It does not cover the numbers inside a tensor. [Schema hash](schema-hash.md) gives the worked value `0xe58aadc7552f0d82`.

## Canonical type text

The canonical type text is the sequence of tokens that names a type, such as `struct{id:i64,batch:tensors,}`. Two programs that hash the same tokens get the same frame hash. The text is not written on the wire. The hash is. Shapes and dtypes inside a directory are data, so they are not tokens.

## Tensor

A tensor is a numeric array with a dtype, a rank, and a shape, whose elements occupy one payload. Kiln uses the word for that block of bits, not for an operation that multiplies matrices. A list of `f32` is the same bits with only a count. A tensor adds the description that lets a later reader know the shape. [A numeric array](array.md) separates the two.

## Directory

A directory is the version-2 block, magic `KLNT`, that holds zero or more tensors. It has a 64-byte header, one 128-byte descriptor per tensor, a name heap, padding to a 64-byte boundary, and the payloads. Its canonical type name, when it appears as a Frozen field, is `tensors`. Version 2 is the only directory version. [Tensor directory](tensor-directory.md) is the layout.

## Descriptor

A descriptor is the 128-byte record that describes one tensor: dtype, rank, name, layout name, quantization indexes, byte offset, byte length, and shape. The descriptor is the table a reader checks. The payload is what the reader then uses. One descriptor per tensor is what makes a hostile count visible before a reader allocates one record per claim.

## Payload

A payload is the byte region that holds one tensor's elements. It starts at an offset that is a multiple of 64, measured from the start of the directory. The alignment exists so the numeric bytes can be used in place after the table has been checked. Gaps between payloads are zeros. A nonzero gap is `TYPE`.

## Name heap

The name heap is the byte region that holds tensor names and then layout names, in descriptor order, with no gaps. The name flag in the header is set exactly when at least one tensor has a name. An empty directory therefore has the flag clear. Names are UTF-8. A bad sequence is `UTF8`. Tensor names are unique as raw bytes.

## Dtype

A dtype is the 16-bit code for an element type. Codes 1 through 19 are the closed set, from `f64` through `e8m0`. Code 0 is rejected. Codes 20 through 4095 are reserved and rejected, so a private experiment cannot pretend to be a standard type. Codes 4096 through 32767 are opaque. [Dtypes](dtypes.md) is the table.

## Rank

The rank is the number of dimensions in a shape. Rank 0 is a scalar, and its element count is 1, even though every shape slot is 0. The maximum rank is 8, because the descriptor stores eight slots and no more.

## Shape

The shape is the list of dimension lengths. Kiln stores eight `u64` slots. Slots at and past the rank are 0. A nonzero slot in that tail is `TYPE`. A zero dimension is legal. The element count is the product of the dimensions in use, and an overflowing product is `LIMIT`.

## Canonical layout

The canonical layout is the one placement of descriptors, names, and payloads that every encoder must write and every decoder must require. Caller order is kept. Payload offsets then advance to the next multiple of 64. One placement means two encoders of the same tensors write one byte string. [Canonical layout](canonical.md) is the procedure.

## View

A view is a read that uses bytes already in the caller's buffer and does not copy the payload into new storage. The view is valid only while that buffer is alive. Kiln specifies the view as a way to use a payload, not as a second wire layout. Profile code 2 names the idea and does not change the bytes.

## Owned copy

An owned copy is a read that writes the payload into storage the result owns. The copy is allocated only after the block has been checked to fit. An implementation may refuse an owned copy above its byte cap with `LIMIT`. A view of a buffer the caller already holds is not subject to the count cap.

## Quantization

Quantization metadata is a link from a data tensor to a scale tensor in the same directory, and for scheme 2 a further link to one outer `f32`. The link exists so a compressed numeric block can travel with the scale that interprets it. Kiln checks the group count. Kiln does not multiply the scale into the elements. [Quantization](quantization.md) states the three schemes.

## Group size

The group size is how many elements along the quantization axis share one scale value. It is 0 when the scheme is 0. For scheme 1 or 2 it is at least 1. The scale tensor's element count must equal `ceil(shape[axis] / group_size)` times the product of the other dimensions. A mismatch is `TYPE`.

## Opaque layout

An opaque layout is a dtype from 4096 through 32767 whose bytes Kiln stores and does not interpret. The descriptor carries a UTF-8 layout name and a block size, and the payload length is a multiple of that block size. The opaque range exists so a foreign block such as `Q4_K` can sit in a Kiln directory without being mistaken for `f32`. [Opaque layouts](opaque.md) is the rule.

## Block size

The block size is the `u32` a descriptor stores for an opaque dtype. It is the size of one foreign block, in bytes. It is 0 for every dtype in the closed set. The payload length must be a multiple of a nonzero block size. The multiple lets a reader check the crate without opening it.

## Alignment

Alignment, in this book, is the rule that each tensor payload starts at an offset that is a multiple of 64 from the start of the directory. Frozen records are not padded to 64. The 64-byte boundary belongs to payloads, where a later reader may want the numeric bytes on a known boundary. The bytes in between are `0x00`.

## Batch

A batch is a list whose element is a struct, or the same struct written on successive calls. On the wire the batch is the list: one count, then the records. Reusing the caller's buffer across calls is an interface choice. It does not appear in the bytes. [A batch of records](batch.md) explains why the repetition matters. A column layout of that batch is profile 4, which this version does not ship.

## Embedding

Embedding is writing a tensor directory as one Frozen field and then continuing with the next field. The directory's length is determined by its header, so the next field has a known start. One buffer can hold an identifier, a string, and the arrays. [Embedding](embedding.md) uses case `kiln-v2-in-struct`.

## Cap

A cap is an implementation limit at or below the maximum the wire allows. A Frozen `u32` count may be as large as 4,294,967,295. The Mojo library's default cap is 16,777,216 counts, and 16 MiB for one string or byte run, until the caller raises it. A value above the cap is `LIMIT`. A value inside the cap that does not fit the buffer is `EOF`. The count cap does not apply to a payload returned as a view of a buffer the caller already holds.

## Magic

Magic is a fixed run of ASCII bytes that identifies a block. The frame magic is `KLN0`. The directory magic is `KLNT`. Magic exists so a reader can reject a different format before it interprets the following bytes as counts. A wrong magic is `FRAME`.

## Golden case

A golden case is a named byte string together with the accept or reject decision and, on a reject, the error code. The cases live in `spec/kiln-v2-cases.json`. They exist so a rule is pinned by bytes, not only by a sentence. [Golden cases](golden.md) is the index of the forty-six cases.

## Dynamic value

A dynamic value is a Kiln value whose schema is a JSON Schema document read at run time, rather than a struct compiled into the program. The generator accepts a documented subset: booleans, integers, numbers, strings, binary strings, arrays, objects, and local `$ref`s. A `tensors` field is not in that subset. [Dynamic values](dynamic.md) is the subset.

## Trusted reader

A trusted reader is a decode path that skips bounds checks because the caller already knows the buffer. `Reader.u8_fast`, `u32_fast`, `u64_fast`, and `str_fast` are that path. They are for a buffer this process just wrote. A hostile length passed to `str_fast` can read off the end of the span. [What a trusted reader may skip](trusted.md) draws the line.

## Depth

Depth is how many containers are nested inside one another: lists, optionals, dicts, structs, and tensor values. Kiln rejects nesting deeper than 64. The limit exists so a hostile or accidental nest cannot recurse without bound. The error is a depth error, separate from `EOF`.

## Error code

An error code is one of seven names a conforming reader uses when it rejects input. The codes are a closed list so two implementations can require the same name for the same fault. The check order of a directory says which fault is reported when several are present.

## FRAME

`FRAME` means the magic, the version, a flag, or a reserved byte is wrong. The reader uses it when the block is not the kind of block it was asked to read. A directory version other than 2 is `FRAME`. A clear little-endian flag is `FRAME`. The code is about the envelope, not about a wrong number inside a valid envelope.

## LIMIT

`LIMIT` means a count is above the configured cap, or a size product overflows an unsigned 64-bit integer. It is distinct from `EOF` so a caller can tell "this implementation refuses that count" from "the buffer is shorter than the count claims." Case `kiln-v2-count-cap` is `LIMIT`. Case `kiln-list-struct-hostile` is `EOF`, because the count is inside the cap and the elements are absent.

## EOF

`EOF` means a length that was checked does not fit in the bytes still unread. The name is the old "end of file." Kiln uses it for a buffer that ends too soon, including a count whose minimum encoding does not fit. The reader returns `EOF` before it allocates element storage for that count.

## TYPE

`TYPE` means a dtype, a shape, a payload range, a name rule, a quantization link, or the canonical placement is wrong. The block was recognized. The description inside it is not a legal Kiln value. A bool byte of 2 is `TYPE`. An overlapping pair of payloads is `TYPE`. A scale chain is `TYPE`.

## UTF8

`UTF8` means a tensor name or a layout name is not valid UTF-8. Kiln checks those names because they are text in the heap. It does not require every payload to be text. A numeric payload is bits. A bad name is `UTF8`, which is separate from `TYPE` so a caller can see that the fault is the text, not the shape.

## TRAILING

`TRAILING` means a standalone buffer continues past the value. The extra bytes are not a second value. They are a signal that the caller passed a buffer the decoder was not asked to slice. A `tensors` field inside a struct does not use `TRAILING` for the bytes of the next field. Those bytes belong to that field.

## SCHEMA

`SCHEMA` means a frame hash does not match the type the reader was given. The reader stops before the first field. `SCHEMA` is not the code for a wrong dtype inside a directory. A wrong dtype is `TYPE`. The frame never claimed to police the shapes. It polices the type text.
