# mojo-kiln

Kiln is a positional little-endian serializer for [Mojo](https://mojolang.org/). The encoder and the decoder are generated from the fields of a Mojo struct when the program compiles. The bytes do not carry field names.

The library is written in Mojo. It does not wrap a C, C++, or Rust serializer. `spec/reference/kiln_ref.py` is a slow reference codec used to produce golden files. It is not used at run time.

Mojo programs need to turn a struct into bytes: a message to another process, a record in a file, or a batch of samples. A format that writes a name or a tag before every value repeats work the compiler has already done, and it takes a branch on every field. The encoders that are fastest on a small fixed record skip that work. They write the fields in source order, as little-endian numbers, and they write a length before each string. Kiln is that encoding for Mojo. `reflect` walks the struct when the program compiles, so a new struct gets a codec without a second library and without a hand-written field list.

The split matters when both sides already share the struct. The names stay in the source. The wire holds the values. A small record is then a handful of stores plus the copy of its strings. A batch is that record repeated, so a per-field branch would be paid once per record. A large array of `Float64` is handled on its own: one header and a raw copy, because those numbers are not named fields.

Documentation: [leo-gan.github.io/gld-kiln](https://leo-gan.github.io/gld-kiln/).

## Install

The published package is `mojo-kiln` for linux-64, on [prefix.dev/leo-gan/leo-gan](https://prefix.dev/leo-gan/leo-gan).

```bash
pixi add --channel https://prefix.dev/leo-gan/leo-gan mojo-kiln
```

The import name is `kiln`. The generator command is `gld-kilngen-mojo`.

## Example

`Point` has two `Int32` fields. Kiln writes them in that order: eight little-endian bytes, and no names. `decode` builds a new `Point` from those bytes. `Writer` keeps its buffer, so the next `encode` can reuse the allocation.

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
    encode(Point(Int32(9), Int32(-4)), w)
    var raw = w.copy_bytes()
    var back = decode[Point](Span(raw))
    print(back.x, back.y, len(raw))
```

The program prints `9 -4 8`.

## License

MIT. Copyright (c) 2026 Leonid Ganeline.
