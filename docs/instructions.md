# Instructions

## Library

```bash
pixi add --channel https://prefix.dev/leo-gan/leo-gan mojo-kiln
```

From a git checkout:

```bash
pixi install
pixi run test
```

Mojo is pinned to 1.1.0. The Modular channel may require `PREFIX_API_KEY` in a local `.env` file. `scripts/ci-setup.sh` reads that file. Do not commit it.

## Encode and decode

A struct needs `Defaultable` so `decode` can build it, and `Movable` so the value can be returned. Declare the fields in the order they should appear on the wire. Kiln writes those values and leaves the names in the source, so two `Int32` fields occupy eight bytes.

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
    var p = Point(Int32(1), Int32(2))
    encode(p, w)
    var raw = w.copy_bytes()
    var back = decode[Point](Span(raw))
    _ = back
```

`Writer` keeps its allocation. The next `encode` clears the length and writes into the same storage when the value fits. `encode_append` does not clear the length.

`decode` checks that each length stays inside the buffer and that strings are UTF-8. Pass `False` as the second argument to skip the UTF-8 check for bytes you already trust.

## Frames and tensors

`encode_framed` writes the 16-byte `KLN0` header and one Frozen value. `decode_framed` checks the magic and the schema hash.

`write_f64` writes a 64-byte `KLNT` header and a raw `Float64` payload. `read_f64` copies that payload back into a list.

## JSON Schema

`gld-kilngen-mojo --schema testdata/schema/point.json --out tests/generated` writes structs whose `encode_to` and `decode_from` call the same reflection codec. The subset is described in the spec: objects, arrays, booleans, integers, numbers, strings, binary strings, and `#/$defs/` references.

`schema_from_json` builds the same description for `encode_value` and `decode_value`, which walk a `Value` tree instead of a Mojo struct. That path is for data whose type arrives at run time. It is not the fast path.
