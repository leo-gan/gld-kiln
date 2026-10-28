# Schema hash {#schema-hash}

The schema hash is an FNV-1a 64-bit mix of the canonical type text. It exists so a [frame](frame-intro.md) can name the type in a fixed number of bytes, without writing the type's source into the buffer.

This page answers which tokens are mixed, and which data are not. Case `kiln-v2-framed` stores the hash of `struct{id:i64,batch:tensors,}` as the little-endian bytes `82 0d 2f 55 c7 ad 8a e5`, which are the integer `0xe58aadc7552f0d82`.

The hash does not include dtypes or shapes inside a directory. A wrong dtype is [`TYPE`](glossary.md#type), not [`SCHEMA`](glossary.md#error-schema).

## Why the hash exists

The hash exists because a positional layout has no names with which to notice that the writer and the reader were built from different structs. If `x` and `y` trade places in the source, the bytes of 9 and −4 trade places, and a reader that does not check will assign them to the wrong fields and succeed. A hash of the type text, compared before the first field, turns that success into `SCHEMA`.

The alternative is a version integer that a programmer remembers to bump. That works when every change bumps it and fails when someone reorders a field and leaves the integer alone. Another alternative is to write the schema into the file, as JSON Schema or as a Protobuf descriptor. The reader can then adapt. Kiln's problem is the reader that should not adapt. It should stop. A third alternative is to hash the whole buffer, which would change whenever a number changed and would not answer the type question at all.

Kiln hashes the canonical type text with FNV-1a 64, a small public function with a fixed basis and a fixed prime, so two languages can implement it without sharing a library. Each token is mixed, then a `0x00` byte, so the boundary between tokens is part of the hash. The new token is `tensors`. The hash does not include dtypes or shapes inside a directory. Those are data. A directory of a different shape, under the same struct type, still matches the frame. A wrong dtype is caught later, as `TYPE`, by the directory rules. Case `kiln-v2-framed` stores `0xe58aadc7552f0d82` for `struct{id:i64,batch:tensors,}`.

This is a good decision because the failure happens before any field is parsed, and because the inputs to the hash are written down. The cost is that the hash is not a migration guide. Adding a field changes the type text, the hash changes, and the old reader stops. There is no "skip the unknown tail." A program that needs that skip should use field numbers. A program that needs to notice a reorder should use this hash.

Analogy. A wax seal shows which edition of a handbook sealed the envelope. It does not contain a translation from the previous edition. Breaking the seal means "do not read this as if it were your edition." It does not mean "here is how the old edition maps onto yours."

| Choice | What it makes cheap | What it makes impossible | What still does that job |
| --- | --- | --- | --- |
| FNV-1a 64 over type tokens, each followed by a `0x00` step | One hash, with a stated basis and prime | A hash that changes when only a tensor's shape changes | The directory's own shape check |
| Stopping on a mismatch before the first field | A wrong struct is not parsed as if it matched | Migrating an old type into a new one | A program that knows both types and converts outside this format |

The hash is FNV-1a 64. The offset basis is 14695981039346656037 and the prime is 1099511628211. Each token is mixed one byte at a time, and each token is followed by the FNV step for a `0x00` byte.

The new token is `tensors`, mixed as those seven ASCII bytes and then the `0x00` step. The hash does not include the dtypes or the shapes inside the directory. Those are data.

For the type `struct{id:i64,batch:tensors,}` the hash is `0xe58aadc7552f0d82`. The framed golden case stores that value as a little-endian `u64` after the 8-byte frame prefix.
