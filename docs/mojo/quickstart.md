# Mojo Quickstart and Examples

This guide covers installing and using `mojo-kiln`, the from-scratch Mojo 1.1.0 reference implementation of [Kiln Wire Format Version 2](../spec/index.md).

## Installation

### From prefix.dev (Package)

```bash
pixi add --channel https://prefix.dev/leo-gan/leo-gan mojo-kiln
```

- **Import module:** `kiln`
- **Code generator CLI:** `gld-kilngen-mojo`
- **Platform / Compiler:** `linux-64`, Mojo `1.1.0`

### From a Git Checkout

```bash
pixi install
pixi run test
```

!!! note
    The Modular channel may require `PREFIX_API_KEY` in a local `.env` file (loaded by `scripts/ci-setup.sh`). Never commit `.env`.

---

## 1. Struct Encode and Decode

Any Mojo struct conforming to `Defaultable` and `Movable` (plus `Copyable` if copied by value) is encoded via compile-time reflection in **field declaration order**. No macros or derive boilerplate are required.

```mojo
from std.collections import Span

from kiln import Writer, decode, encode


@fieldwise_init
struct Point(Copyable, Movable, Defaultable):
    var x: Int32
    var y: Int32

    def __init__(out self):
        self.x = 0
        self.y = 0


def main() raises:
    var w = Writer(64)
    encode(Point(Int32(9), Int32(-4)), w)  # writes 8 little-endian bytes
    var raw = w.copy_bytes()
    var back = decode[Point](Span(raw))
    print(back.x, back.y, len(raw))        # 9 -4 8
```

- `Writer` retains its backing buffer across calls: subsequent `encode` calls reset `w.length = 0` and reuse the existing allocation without reallocating when the value fits. Use `encode_append` to append without resetting.
- `decode` enforces pre-allocation bounds checks, strict UTF-8 validation, and exact buffer consumption (`TRAILING`). Pass `check_utf8=False` only for trusted buffers produced inside the same trust boundary.
- Source: `examples/roundtrip.mojo`.

---

## 2. Framed I/O (Schema Fingerprint Seal)

Use `encode_framed` and `decode_framed` whenever bytes cross process, file, or deployment boundaries. A 16-byte `KLN0` header stores the FNV-1a-64 schema hash and rejects a mismatched struct with `KilnError.SCHEMA` before reading field 0.

```mojo
from std.collections import Span

from kiln import Writer, decode_framed, encode_framed


def roundtrip_framed(p: Point) raises -> Point:
    var w = Writer(64)
    encode_framed(p, w)
    var raw = w.copy_bytes()
    return decode_framed[Point](Span(raw))
```

---

## 3. Tensor Directories (`KLNT` v2)

`TensorDir` conforms to `KilnCodec` and `KilnMin`, so it can be encoded standalone or embedded directly as a struct field (`tensors`). `f64_directory` constructs a single unnamed `f64` tensor from a `List[Float64]`.

```mojo
from std.collections import List, Span

from kiln import TensorDir, Writer, decode, encode, f64_directory


def main() raises:
    var values = List[Float64]()
    values.append(1.5)
    values.append(-2.0)
    values.append(0.0)

    var dir = f64_directory(values)
    var w = Writer(256)
    encode(dir, w)

    var back = decode[TensorDir](Span(w.copy_bytes()))
    print(len(back.items), back.items[0].shape[0], len(back.items[0].data))  # 1 3 24
```

For multi-tensor directories with names, low-precision dtypes (`DTYPE_F16`, `DTYPE_BF16`, `DTYPE_F8E4M3`, `DTYPE_E2M1`, etc.), quantization scale links, or opaque layouts, construct `KilnTensor` entries and append them to `TensorDir.items`. See `tests/test_tensor.mojo` and `tests/test_tensor_v2.mojo`.

---

## 4. Generating Mojo Structs from JSON Schema

`gld-kilngen-mojo` compiles the [portable JSON Schema subset](../spec/index.md#dynamic-values) into Mojo structs with `encode_to`, `decode_from`, and `encoded_len` methods backed by the same compile-time reflection codec:

```bash
gld-kilngen-mojo --schema testdata/schema/point.json --out tests/generated
```

```mojo
from std.collections import Optional, Span

from Point import Point
from kiln import Writer


def main() raises:
    var p = Point()
    p.x = 3
    p.y = -1
    p.label = Optional[String](String("a"))

    var w = Writer()
    p.encode_to(w)
    var back = Point.decode_from(Span(w.copy_bytes()))
```

Regenerate and verify checked-in generated sources with `pixi run generate` and `pixi run check-generated`. See `tests/test_gen.mojo`.

---

## 5. Runtime Dynamic Values

When the schema arrives at run time rather than compile time, `schema_from_json` builds a `Schema` for `encode_value` / `decode_value` over a `Value` tree. Bytes produced by `encode_value` are byte-identical to reflection-encoded structs for the same schema (verified in `tests/test_value.mojo`). This path is intended for tooling and dynamic ingestion, not minimum-latency hot loops.

```mojo
from std.collections import Span

from kiln import Value, decode_value, encode_value_bytes, schema_from_json


def main() raises:
    var text = '{"title":"Point","type":"object","properties":{"x":{"type":"integer","format":"int32"},"y":{"type":"integer","format":"int32"}},"required":["x","y"]}'
    var schema = schema_from_json(text)

    var v = Value()
    var root = v.start_struct()
    v.push(root, v.add_i64(Int64(9)))
    v.push(root, v.add_i64(Int64(-4)))
    v.root = root

    var raw = encode_value_bytes(schema, v)
    var back = decode_value(schema, Span(raw))
    _ = back
```
