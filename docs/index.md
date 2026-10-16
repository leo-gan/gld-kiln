# Kiln

Kiln encodes a Mojo struct as little-endian fields in declaration order. The compiled program already knows the type, so the bytes do not contain field names or field numbers.

The library exists for the exchange where both sides already share that struct: a message, a file record, or a batch of samples. Writing a name before each value spends bytes and a branch to repeat what the compiler knows. Kiln keeps the names in the Mojo source and writes only the values. [Why Kiln](why-kiln.md) explains the batch case, the tensor block for a raw array of `Float64`, and the decision to reject a changed struct instead of evolving the file in place.

The library is from-scratch Mojo. A Python reference codec writes the golden files. It is not linked into the encoder.

| | |
| --- | --- |
| Import | `kiln` |
| Package | `mojo-kiln` on prefix.dev, linux-64 |
| Generator | `gld-kilngen-mojo` |
| Wire | Frozen profile, version 0 |
| Mojo | 1.1.0 |

On an Intel i7-12800H, powersave governor, one pinned core, Mojo 1.1.0, `experiments/decode_small.mojo` measured a 44-byte message at mean 15 ns to encode and mean 36 ns to decode into owned strings. A batch of 100 messages encodes in mean 345 ns and decodes in mean 3.09 µs when UTF-8 is checked. These are not dashboard ranks. The [experiments](experiments.md) page records the machine and the decisions.
