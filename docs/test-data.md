# Test data

| Path | What it checks |
| --- | --- |
| `tests/test_roundtrip.mojo` | Scalars, a nested struct, a list, a dict, a frame, and depth. |
| `tests/test_golden.mojo` | Bytes match `spec/golden/`, which the Python reference wrote. |
| `tests/test_malformed.mojo` | Truncation, a bad boolean, a huge length, bad UTF-8, trailing bytes, a bad frame, and a string view. |
| `tests/test_fuzz.mojo` | Fifty random messages round-trip. Random prefixes must raise rather than crash. |
| `tests/test_value.mojo` | A JSON Schema and a `Value` tree match reflection. |
| `tests/test_gen.mojo` | Generated `Point` and `Message` round-trip. |
| `tests/test_tensor.mojo` | Three `Float64` values survive one tensor in a directory. |
| `tests/test_tensor_v2.mojo` | Version-2 directory, struct embedding, allocation, and byte order. |
| `testdata/schema/` | JSON Schema files the generator reads. |

Regenerate the golden files with `python3 spec/reference/gen_golden.py`. Regenerate the structs with `pixi run generate`. `pixi run check-generated` diffs them against `tests/generated/`.
