# Kiln — a frozen, positional wire format in 11 languages

Kiln is a little-endian wire format with from-scratch implementations in 11
languages, golden-file tested against one spec. No field names on the wire:
both sides are built from the same struct, so Kiln writes values in field
order and nothing else. A 44-byte message encodes in ~15 ns and decodes in
~28 ns (Mojo, measured, machine documented).

**Spec + docs:** https://leo-gan.github.io/gld-kiln
**Implementations:** Mojo (this repo) · Go · Rust · Zig · C · C++ · Python ·
Java · Swift · C# · TypeScript — each an independent from-scratch codec.

## Why positional?

JSON writes the names next to the values: `{"id": 7, "label": "cat"}`.
Kiln writes only the values, in the order the struct declares them. The names
stay in the source code. The price: a reader built from a different struct
stops instead of guessing — there are no names on the wire to look up.

## Benchmarks (Mojo, measured)

| Message | Encoded size | Encode | Decode |
| --- | ---: | ---: | ---: |
| 44-byte message | 44 bytes | ~15 ns | ~28 ns |

Full numbers and methodology: https://leo-gan.github.io/gld-kiln (machine
documented with every run).

## Install

The published package is `mojo-kiln` for linux-64, on
[prefix.dev/leo-gan/leo-gan](https://prefix.dev/leo-gan/leo-gan).

```bash
pixi add --channel https://prefix.dev/leo-gan/leo-gan mojo-kiln
```

The import name is `kiln`. The generator command is `gld-kilngen-mojo`.

## Example

`Point` has two whole-number fields. Kiln writes those two values and does
not write the names. `decode` builds a new `Point` from those bytes. `Writer`
keeps its buffer, so the next `encode` can reuse the allocation.

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

The program prints `9 -4 8`. The `8` is the number of bytes for those two
integers.

## Learn more

- Introduction for readers who know JSON and one or two other formats:
  https://leo-gan.github.io/gld-kiln/spec/first/
- Full specification (wire format, version 2):
  https://leo-gan.github.io/gld-kiln/spec/

## License

MIT. Copyright (c) 2026 Leonid Ganeline.

---

*If Kiln is useful to you, a star on this repo (and any language codec you
use) is the fastest way to help it grow.*
