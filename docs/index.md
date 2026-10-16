# Kiln

Kiln encodes a Mojo struct as little-endian fields in declaration order. The compiled program already knows the type, so the bytes do not contain field names or field numbers.

The library is from-scratch Mojo. A Python reference codec writes the golden files. It is not linked into the encoder.

| | |
| --- | --- |
| Import | `kiln` |
| Package | `mojo-kiln` on prefix.dev, linux-64 |
| Generator | `gld-kilngen-mojo` |
| Wire | Frozen profile, version 0 |
| Mojo | 1.1.0 |

On an Intel i7-12800H, powersave governor, one pinned core, Mojo 1.1.0, `experiments/harness.mojo` measured a 44-byte message at about 38 ns to encode and about 90 ns to decode into owned strings. A batch of 100 encodes in about 3.0 µs. Reading that batch back with the unchecked view reader adds about 0.30 µs. Owned decoding allocates the strings, so a batch of owned values costs more. These are not dashboard ranks. The [experiments](experiments.md) page records the machine and the decisions.
