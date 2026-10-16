# Kiln wire format, version 0

Kiln is a positional binary format. The reader knows the type, so the bytes do not carry field names or field numbers. Multi-byte integers are little-endian. This is the normative description of profile 0, Frozen.

The Python module `spec/reference/kiln_ref.py` is the reference codec. Golden files under `spec/golden/` are bytes that module produced. The Mojo library is checked against those files.

## Profiles

| Code | Name | Status in this version |
| --- | --- | --- |
| 0 | Frozen | Normative. This is the default. |
| 1 | Evolve | Specified as an experiment. Not the default API. |
| 2 | View | Not a separate layout. In-place reads use the Frozen bytes. |
| 3 | Tensor | Normative for `write_f64` / `read_f64`. |
| 4 | Columns | Not shipped. The batch experiment did not beat a separate columnar layout by enough to add a second encoder. |

## Frozen values

There is no padding between fields. A struct is the concatenation of its fields in declaration order.

| Mojo type | Canonical name | Encoding |
| --- | --- | --- |
| `Bool` | `bool` | One byte, 0 or 1. Any other byte is a type error. |
| `Int8` | `i8` | One byte, two's complement. |
| `Int16` | `i16` | Two bytes, little-endian. |
| `Int32` | `i32` | Four bytes, little-endian. |
| `Int64` | `i64` | Eight bytes, little-endian. |
| `Int` | `int` | Eight bytes, little-endian. The width does not follow the pointer size. |
| `UInt8` | `u8` | One byte. |
| `UInt16` | `u16` | Two bytes, little-endian. |
| `UInt32` | `u32` | Four bytes, little-endian. |
| `UInt64` | `u64` | Eight bytes, little-endian. |
| `UInt` | `uint` | Eight bytes, little-endian. |
| `Float32` | `f32` | Four bytes, IEEE-754 little-endian. |
| `Float64` | `f64` | Eight bytes, IEEE-754 little-endian. The bit pattern is preserved, including a NaN payload and negative zero. |
| `String` | `str` | `u32` byte length, then UTF-8 bytes. No terminator. |
| `List[UInt8]` | `list<u8>` | `u32` count, then that many bytes. |
| `List[T]` | `list<...>` | `u32` count, then the elements. A list of a fixed-width number is a raw copy on a little-endian host. |
| `Optional[T]` | `opt<...>` | One byte, 0 or 1. A 1 is followed by the inner value. |
| `Dict[String, V]` | `dict<str,...>` | `u32` count, then key/value pairs. Keys are written in lexicographic byte order so two encodes of the same map match. |

A string or a byte run longer than 16 MiB is a limit error. A list count greater than 16,777,216 is a limit error. A length that extends past the buffer is an end-of-buffer error, and the decoder does not allocate from that length. Nesting deeper than 64 containers is a depth error. `decode` requires the buffer to contain exactly one value.

`List[UInt8]` and a byte blob have the same layout. The schema hash still treats `list<u8>` and a dynamic `bytes` type as different types.

## Schema hash

A frame carries an FNV-1a 64-bit hash of the canonical type text. The offset basis is 14695981039346656037 and the prime is 1099511628211. Each token is mixed one byte at a time, and each token is followed by the FNV step for a 0x00 byte. That step is a multiply, because XOR with zero does not change the hash.

A struct token is `struct{`, then for each field the field name, `:`, the field's type text, and `,`, then `}`. Names and types are hashed in declaration order. Container text is `list<...>`, `opt<...>`, and `dict<str,...>`.

## Frame

An in-memory value has no frame. `encode_framed` writes 16 bytes and then one Frozen value.

| Offset | Size | Contents |
| --- | --- | --- |
| 0 | 4 | ASCII `KLN0` |
| 4 | 1 | Profile code. Frozen is 0. |
| 5 | 1 | Flags. This version writes 0. |
| 6 | 2 | Reserved. This version writes 0. |
| 8 | 8 | Schema hash, little-endian. |

`decode_framed` rejects a wrong magic, a profile other than Frozen, or a hash that does not match the destination type.

## Tensor block

`write_f64` writes a 64-byte header and then raw little-endian `Float64` values.

| Offset | Size | Contents |
| --- | --- | --- |
| 0 | 4 | ASCII `KLNT` |
| 4 | 1 | Version 1. |
| 5 | 1 | Dtype 1, which means `Float64`. |
| 6 | 2 | Reserved 0. |
| 8 | 8 | Element count, little-endian. |
| 16 | 48 | Zeros. The payload starts at offset 64. |

## Dynamic values

`schema_from_json` reads a JSON Schema subset: `boolean`, `integer` with an optional `format` (`int8` through `int64`, `uint8` through `uint64`), `number` (`float` or the default `double`), `string`, `string` with `"format": "binary"`, `array`, `object`, and `$ref` of the form `#/$defs/Name`. A property listed in `required` is present. A property left out of `required` is `opt<...>`. If `required` is omitted, every property is present. An object whose only value schema is `additionalProperties` is a `Dict[String, V]`.

The generator `gld-kilngen-mojo` emits one Mojo file of structs. Those structs use the same `encode` and `decode` as a hand-written struct.

## What a trusted reader may skip

`decode` checks bounds and UTF-8. `Reader.u8_fast`, `u32_fast`, `u64_fast`, and `str_fast` do not. They are for a buffer this process just encoded, or another buffer whose length was already checked. A hostile length passed to `str_fast` can read off the end of the span.
