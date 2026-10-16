# Examples

These programs follow the README example. A struct goes in, the field values come out in declaration order, and `decode` builds the struct again. The field names stay in the source.

`examples/roundtrip.mojo` encodes a struct, decodes it, and checks the fields.

A generated struct from `testdata/schema/point.json` has `x`, `y`, and an optional `label`. `tests/test_gen.mojo` builds one, calls `encode_to`, and reads it back with `decode_from`.

The dynamic API uses the same bytes as reflection when the schema describes the same fields. `tests/test_value.mojo` encodes a `Point` both ways and compares the buffers.

Golden bytes for the eight-field message live in `spec/golden/message.kiln`. `tests/test_golden.mojo` encodes that message and requires a byte-for-byte match, including the framed file.
