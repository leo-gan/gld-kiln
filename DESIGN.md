# Kiln design

Kiln is a positional little-endian codec. `reflect` walks a struct at compile time. The caller owns a `Writer` and reuses it. `decode` is checked. `Reader.*_fast` is the unchecked reader for a buffer this process already bounded.

## Decisions

| Topic | Choice |
| --- | --- |
| Wire | Kiln's own Frozen layout. Not speedy, bincode, comptime-bin, or dagr bytes. |
| Profiles shipped | Frozen, and the tensor directory (`tensors`, version 2). There is no earlier tensor layout. Evolve, a separate view layout, and columns stay out. See `docs/experiments.md`. |
| API | `encode` / `decode` on Mojo structs, a `Value` tree driven by JSON Schema, and `gld-kilngen-mojo`. |
| Lengths | `u32` byte counts. Dict keys are sorted. |
| Errors | `KilnError`. A length past the buffer does not allocate. |
| Package | `mojo-kiln`, import `kiln`, Mojo 1.1.0, MIT, linux-64. |

## Pull requests

The first push is the library, tests, experiments, and docs at version 0.1.0. After `main` is protected, the version bump to 0.2.0 is its own pull request and is what publishes the conda package.

## Benchmark row

`seriailizer-benchmark` vendors `src/kiln` and times `kiln` on the five suite record types. `Fixture.empty` avoids copying five lists during deserialize for Kiln and for the CBOR, Avro, EmberJson, and BSON rows that used that copy.
