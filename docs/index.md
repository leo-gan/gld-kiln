# Kiln

Kiln stores the values of a Mojo struct so another program, built from that same struct, can rebuild them. Storing values so they can be sent or saved is called serialization. JSON does this by writing the names and the values as text.

A reader who knows JSON, and has only heard that word, should start with the [repository README](https://github.com/leo-gan/gld-kiln#readme). The specification opens with [Introduction](spec/first.md), then the [contents](spec/index.md).

The library is from-scratch Mojo. A Python reference codec writes the golden files. It is not linked into the encoder.

| | |
| --- | --- |
| Import | `kiln` |
| Package | `mojo-kiln` on prefix.dev, linux-64 |
| Generator | `gld-kilngen-mojo` |
| Wire | Frozen profile, tensor directory version 2 |
| Mojo | 1.1.0 |

On an Intel i7-12800H, powersave governor, one pinned core, Mojo 1.1.0, `experiments/decode_small.mojo` measured a 44-byte message at mean 15 ns to encode and mean 28 ns to decode into owned strings. A batch of 100 messages encodes in mean 339 ns and decodes in mean 1.56 µs when UTF-8 is checked. These are not dashboard ranks. The [experiments](experiments.md) page records the machine and the decisions.
