# mojo-kiln

A program can hold a small record as JSON text. One record is an id and a short label: `{"id": 7, "label": "cat"}`. The names `id` and `label` are written in that text, next to the values.

Serialization is turning those values into a form that can be stored or sent, so another program can rebuild them. JSON text is one such form. Kiln is another form. It is a library for [Mojo](https://mojolang.org/), the programming language this project is written in.

Kiln is for the case where both programs are built from the same struct. A struct is the list of fields in the source code, in a fixed order. Kiln writes the values in that order. The names stay in the source. The other program reads the values back into those same fields.

JSON still shows a new name when a field is added later. A Kiln reader built from a different struct stops, because the bytes hold values and no names to look up.

The next page is for a reader who already knows JSON and one or two other formats: [Introduction](https://leo-gan.github.io/gld-kiln/spec/first/). The full specification starts at [Kiln wire format, version 2](https://leo-gan.github.io/gld-kiln/spec/).

## Install

The published package is `mojo-kiln` for linux-64, on [prefix.dev/leo-gan/leo-gan](https://prefix.dev/leo-gan/leo-gan).

```bash
pixi add --channel https://prefix.dev/leo-gan/leo-gan mojo-kiln
```

The import name is `kiln`. The generator command is `gld-kilngen-mojo`.

## Example

`Point` has two whole-number fields. Kiln writes those two values and does not write the names. `decode` builds a new `Point` from those bytes. `Writer` keeps its buffer, so the next `encode` can reuse the allocation.

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

The program prints `9 -4 8`. The `8` is the number of bytes for those two integers.

## License

MIT. Copyright (c) 2026 Leonid Ganeline.
