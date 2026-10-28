# Glossary

Each entry is the short definition. The same terms are explained at length, including why the word is needed, on [Terminology](terminology.md). The link after a short definition opens the chapter that states the rule.

## Serialization

Serialization is turning values into a form that can be stored or sent, so another program can rebuild them. JSON text is one such form. The [repository README](https://github.com/leo-gan/gld-kiln#readme) defines the word for a reader who has only heard it. This book specifies Kiln's form.

## Schema

A schema is the description of a value's fields, their types, and their order. In Kiln the schema is the struct in the program, and it is not repeated in the bytes. [Schema and declaration order](schema.md).

## Wire

The wire is the sequence of bytes that one program writes and another reads. The same bytes may sit in a file. Nothing in the word requires a network.

## Positional

A positional encoding writes values in a fixed order and does not write a name or a number in front of each value. The reader uses the schema to know which value comes next. [The same record in three encodings](record.md).

## Little-endian

Little-endian order stores the least significant byte of a multi-byte number first. Kiln uses that order for every multi-byte integer and every multi-byte floating-point value, on every machine. [Byte order](byte-order.md).

## Frozen

Frozen is Kiln's default layout, profile code 0. Fields are written in declaration order, with no names and no padding between them. [Frozen values](frozen.md).

## Frame

A frame is a 16-byte prefix in front of one Frozen value. It carries a hash of the type. A reader that was given a different type stops before the first field. [Frame](frame.md).

## Tensor

A tensor is a numeric array with a [dtype](#dtype), a [rank](#rank), and a [shape](#shape). Its elements occupy one [payload](#payload). [A numeric array](array.md).

## Directory

A directory is the version-2 block that holds zero or more tensors: a header, one descriptor per tensor, an optional name heap, and the payloads. Its canonical type name is `tensors`. [Tensor directory](tensor-directory.md).

## Payload

A payload is the byte region that holds one tensor's elements. Each payload starts at an offset that is a multiple of 64 from the start of its directory. [Tensor directory](tensor-directory.md).

## Dtype

A dtype is the numeric code for one element type, such as `f32` or `i64`. Codes 1 through 19 are the closed set. [Dtypes](dtypes.md).

## Rank

The rank is how many dimensions a tensor's shape has. Rank 0 is a scalar, and its element count is 1. The maximum rank is 8. [Tensor directory](tensor-directory.md).

## Shape

The shape is the list of dimension lengths. Kiln stores eight slots. Slots at and past the rank are 0. A nonzero slot in that tail is [`TYPE`](#type). [Tensor directory](tensor-directory.md).

## Canonical

A canonical layout is the one byte string every encoder must write for the same value. A decoder rejects a block that is otherwise well formed but placed differently. [Canonical layout](canonical.md).

## View

A view is a read that uses bytes already in the caller's buffer and does not copy the payload into a new allocation. The buffer must remain alive as long as the view is used. [Lengths and allocation](lengths.md).

## Owned copy

An owned copy is a read that writes the payload into storage the result owns. That storage is allocated only after the block has been checked to fit. [Lengths and allocation](lengths.md).

## Quantization

Quantization metadata names a scale tensor, and for one scheme an outer scale, stored beside the data tensor. Kiln checks the element counts and does not multiply the scale into the data. [Quantization](quantization.md).

## Opaque layout

An opaque layout is a dtype code from 4096 through 32767. Kiln checks the layout name and the block size, and it does not interpret the block. [Opaque layouts](opaque.md).

## Cap

A cap is an implementation limit at or below the wire's maximum count. The Mojo default is 16,777,216 counts, and 16 MiB for one string or byte run, until the caller raises it. A value above the cap is [`LIMIT`](#limit). [Lengths and allocation](lengths.md).

## FRAME {#error-frame}

`FRAME` means the magic, the version, a flag, or a reserved byte is wrong. The reader stops before trusting the rest of the block. [Errors](errors.md).

## LIMIT

`LIMIT` means a count is above the cap, or a size product overflows an unsigned 64-bit integer. [Errors](errors.md).

## EOF

`EOF` means a length that was checked does not fit in the bytes still unread. [Errors](errors.md).

## TYPE

`TYPE` means a dtype, a shape, a payload range, a name, a quantization link, or the canonical placement is wrong. [Errors](errors.md).

## UTF8

`UTF8` means a tensor name or a layout name is not valid UTF-8. [Errors](errors.md).

## TRAILING

`TRAILING` means a standalone buffer continues past the value. A `tensors` field inside a struct does not use this code for the bytes of the next field. [Errors](errors.md).

## SCHEMA {#error-schema}

`SCHEMA` means a frame hash does not match the type the reader was given. [Errors](errors.md).
