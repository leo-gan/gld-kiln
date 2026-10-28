# Golden cases {#golden-cases}

A golden case is a named byte string, an expected accept or reject, and the error code when it rejects. The cases exist so a change to a rule is visible as a change to bytes, not only as a change to prose.

Forty-six cases are listed below. Their hex lives in `spec/kiln-v2-cases.json`. Regenerating that file reruns the checks. A case that fails with a different code than the table must not be written out.

`tests/test_tensor_v2.mojo` checks the same rules in the Mojo library.

## Why the cases exist

The cases exist because a sentence and a table can be implemented two ways, and the bytes cannot. Each case is a hex string, an accept or a reject, and on a reject the error code from [Check order](check-order.md). The generator `spec/reference/gen_v2_cases.py` builds the file and refuses to write it if a case fails at a different code from the one recorded here. That refusal is the point. A prose edit that drifts from the bytes does not silently update the oracle.

The alternative is tests that live only inside one language, next to one library. Those tests are necessary. `tests/test_tensor_v2.mojo` is one of them. They do not travel to the Python, Rust, C, and other ports, which implement the same wire. A shared JSON file does. Another alternative is to publish only the accept cases, the happy path. The reject cases are the ones that pin `EOF` before allocation, the clear little-endian flag, the odd packed nibble, and the scale count. Without them, a fast reader that skips a check still looks conformant.

Kiln keeps forty-six cases, not a generated fuzz corpus, in the specification. Fuzzing belongs in a library's tests. The specification pins the decisions a human argued about: empty directory, negative zero, NaN payload, name flag, alignment, both quantization schemes, `Q4_K` as opaque, a directory inside a struct, a frame hash, and the hostile counts. Regenerating the file rewrites section URLs when headings move. It does not rewrite a byte unless the reference codec changed, and a changed codec that disagrees with a recorded error stops the script.

This is a good decision because the wire has many corners where a convenient implementation would diverge: host endian, allocate-then-check, dequantizing on read, accepting any payload offset. Each of those has a case that fails. The cost is a JSON file that must be regenerated rather than hand-edited, and a table here that must keep every id. An id missing from this page is a case the book no longer explains.

Analogy. A museum keeps the reference object in a case, not only the caption. Two visitors can disagree about the caption and then look at the object. The hex is the object. This table is the label on the case.

| Choice | What it makes cheap | What it makes impossible | What still does that job |
| --- | --- | --- | --- |
| One hex string per case | Two implementations can compare bytes | A prose rule with no pinned input | There is no such rule in this table. Each row names a case |
| The first error from [Check order](check-order.md) | The expected code is unique | Recording a second fault in the same block | A later case that isolates that fault |

Forty-six cases are in `spec/kiln-v2-cases.json`. Each case has the hex, the expected accept or reject, and the error code when it rejects. Regenerate them with:

```bash
python3 spec/reference/gen_v2_cases.py
```

The script refuses to write the file if a case does not fail at the error recorded here. `tests/test_tensor_v2.mojo` checks the same rules in the Mojo library.

| Case | Result | What it pins |
| --- | --- | --- |
| `kiln-v2-empty` | accept | Header-only directory |
| `kiln-v2-f32` | accept | `f32` bits, one descriptor, endian |
| `kiln-v2-f32-scalar` | accept | Rank 0 |
| `kiln-v2-f32-negzero` | accept | Sign of zero |
| `kiln-v2-f64-nan` | accept | NaN payload bits |
| `kiln-v2-f16-named` | accept | Name heap and zero pad |
| `kiln-v2-bf16` | accept | `bf16` 1.0 |
| `kiln-v2-i8` | accept | Two's complement |
| `kiln-v2-bool` | accept | One byte per bool |
| `kiln-v2-u4` | accept | Low nibble first |
| `kiln-v2-f8-pair` | accept | Both f8 codes and offset 64 |
| `kiln-v2-scales` | accept | Scheme 1, MXFP4-shaped block |
| `kiln-v2-scales-outer` | accept | Scheme 2, outer `f32` |
| `kiln-v2-opaque` | accept | Layout name `Q4_K` |
| `kiln-v2-in-struct` | accept | Directory after an `i64` |
| `kiln-v2-framed` | accept | Hash of the `tensors` token |
| `kiln-pod-list-f32` | accept | List of `f32` that fits |
| `kiln-v2-bad-magic` | `FRAME` | Magic |
| `kiln-v2-bad-version` | `FRAME` | Directory version other than 2 |
| `kiln-v2-empty-name-flag` | `TYPE` | Name flag on an empty directory |
| `kiln-v2-le-clear` | `FRAME` | Little-endian flag |
| `kiln-v2-unknown-flag` | `FRAME` | Unknown flag |
| `kiln-v2-reserved` | `FRAME` | Reserved header byte |
| `kiln-v2-directory-eof` | `EOF` | Count whose directory does not fit |
| `kiln-v2-count-cap` | `LIMIT` | Count 16,777,217 at the default cap |
| `kiln-v2-directory-mismatch` | `TYPE` | `directory_bytes` |
| `kiln-v2-shape-overflow` | `LIMIT` | Shape product |
| `kiln-v2-length-mismatch` | `TYPE` | Width times count |
| `kiln-v2-overlap` | `TYPE` | Overlapping ranges |
| `kiln-v2-unaligned` | `TYPE` | Canonical offset |
| `kiln-v2-nonzero-pad` | `TYPE` | Zero padding |
| `kiln-v2-duplicate-name` | `TYPE` | Unique names |
| `kiln-v2-bad-utf8` | `UTF8` | Name bytes |
| `kiln-v2-bool-byte` | `TYPE` | Bool byte 2 |
| `kiln-v2-scale-count` | `TYPE` | One scale per group |
| `kiln-v2-opaque-no-layout` | `TYPE` | Opaque layout required |
| `kiln-v2-trailing` | `TRAILING` | Standalone length |
| `kiln-v2-high-nibble` | `TYPE` | Odd packed tail |
| `kiln-v2-shape-tail` | `TYPE` | Shape slots past the rank |
| `kiln-v2-dtype-zero` | `TYPE` | Code 0 |
| `kiln-v2-dtype-reserved` | `TYPE` | Code 20 |
| `kiln-v2-payload-overflow` | `LIMIT` | `payload_bytes` near 2^64 |
| `kiln-list-struct-hostile` | `EOF` | Count 16,777,216 and no elements |
| `kiln-list-struct-short` | `EOF` | Two structs, one present |
| `kiln-list-str-short` | `EOF` | Three strings, one length present |
| `kiln-pod-list-short` | `EOF` | Two `f32`, four payload bytes |
