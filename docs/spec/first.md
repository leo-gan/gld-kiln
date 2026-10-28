# Introduction

This page is for a developer who has used JSON and Protocol Buffers, and one further format such as MessagePack or CBOR. It places Kiln beside those formats on one struct. Later chapters give the byte tables. The words those chapters use are defined in [Terminology](terminology.md).

The struct is `Point`. The field `x` is declared before `y`. Both are 32-bit integers. The values are 9 and −4.

JSON writes the names and the values as text. The characters `{"x":9,"y":-4}` are 14 bytes. A reader learns which value is which by reading the names. MessagePack stores a map the same way: the names are in the bytes, and a type tag replaces the punctuation in front of each value. CBOR does that too, with its own tags.

Protocol Buffers writes a field number in front of each value. The number is what lets a reader skip a field that its own definition does not contain. This illustration uses Protobuf type `int32`, field 1 for `x` and field 2 for `y`. It is not a Kiln rule. The bytes are `08 09 10 fc ff ff ff ff ff ff ff ff 01`, thirteen bytes. The value 9 occupies one byte after its tag. The value −4 occupies ten bytes, because a negative `int32` is widened to a 64-bit varint. A Protobuf `sint32` would zigzag −4 into a short varint instead. Kiln uses neither form.

Kiln writes the values in declaration order. Names and field numbers are left out. The file `spec/golden/point.kiln` is `09 00 00 00 fc ff ff ff`, eight bytes. The first four bytes are 9. The next four are −4. The least significant byte of each integer comes first. Both programs were built from the same struct, so each side already knows which four bytes are `x`.

A string is the value whose size the schema does not know in advance, so Kiln writes a count and then the text. In `spec/golden/message.kiln` the text `hi` is the four-byte count `02 00 00 00` and then the bytes `68 69`. The count belongs to the value. The field name is still absent. JSON would have written that name as well as the letters.

An unknown field cannot be skipped. If the writer adds a third field, a reader built from the two-field struct has no name and no number to jump over. It stops. [The frame](frame-intro.md) explains how a reader can notice that the struct no longer matches, before it reads the first value.

One record is a handful of values. `Point` is eight bytes and a direct read of two integers.

A batch is that record repeated. A batch of one hundred copies is one hundred times the record. Work done once per field is paid once per record. The names in a JSON array of objects would be written on every copy. Kiln does not write them. A format that branches on a name or a field number pays that branch on every copy.

A large array of numbers is one block of bits, not a walk from element to element. A list of 32-bit floats is a count and then the floats. Case `kiln-pod-list-f32` is the count 2, then 1.0, then −2.0: `02 00 00 00 00 00 80 3f 00 00 00 c0`.

When one record holds several arrays, and each array has a shape, Kiln stores those arrays in a [directory](directory-intro.md) inside the record.

## Where to go next

- [The same record in three encodings](record.md)
- [Schema and declaration order](schema.md)
- [Widths, lengths, and byte order](widths.md)
- [Lists and a count that must fit](lists.md)
- [A batch of records](batch.md)
- [A numeric array](array.md)
- [Names, scales, and foreign blocks](directory-intro.md)
- [The frame](frame-intro.md)
- [What this version leaves out](omitted.md)
- [Glossary](glossary.md)
- [Contents](index.md)
