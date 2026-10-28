# Errors {#errors}

An error code is the name of a failure a conforming reader returns. The codes are a closed list so a case can require one of them and not a paraphrase.

This page is that list. Each code is also defined in the [glossary](glossary.md). [`SCHEMA`](glossary.md#error-schema) is the frame error for a hash that does not match the destination type. The sentence after the table repeats that fact because a frame mismatch is not a dtype mismatch: a dtype mismatch is [`TYPE`](glossary.md#type).

## Why there are seven codes

Seven codes exist so a caller and a test can branch on a small closed set, and so two implementations can be wrong in a way a case can see. A single error would force every caller to parse a message string. A code per golden case would make the set grow every time a new fault is pinned, and the caller would learn nothing stable.

The split inside the seven is the design. `FRAME` is "this is not the block you think." `SCHEMA` is "this is a Kiln frame, and it is not your type." `LIMIT` is "the number is above what this implementation will allocate, or the arithmetic overflowed." `EOF` is "the buffer ended before the claim could be true." `TYPE` is "the block is the right kind, and the description inside it is illegal." `UTF8` is the text fault, separated from `TYPE` so a bad name is not mistaken for a bad shape. `TRAILING` is "you passed a standalone buffer that continues." A `tensors` field does not use `TRAILING` for the next field's bytes.

The alternative of rich diagnostics is a good debugger and a bad conformance target. Kiln keeps the rich text out of the wire rule. An implementation may attach a sentence. The case requires the code. `SCHEMA` is repeated after the table because it is easy to file a hash mismatch under `TYPE`. A dtype error is `TYPE`. The frame never hashed the dtype.

This is a good decision for a library that will be called from generated code and from tests. The caller writes seven arms, or it writes one arm that aborts. The cost is that a human reading only the code does not learn which byte was wrong. The case id, in [Golden cases](golden.md), is the name of the situation. The code is the class of the situation.

Analogy. A counter has seven stamps. Every rejected form gets one stamp. The customer learns which desk to return to. A counter that writes a fresh paragraph on each form is kinder and cannot be compared with the counter next door.

| Choice | What it makes cheap | What it makes impossible | What still does that job |
| --- | --- | --- | --- |
| Seven codes | A caller branches on a small set | A distinct code for every rejected case | The case id in [Golden cases](golden.md), which names the situation |
| `LIMIT` distinct from `EOF` | A cap failure is not reported as a short buffer | Treating every refusal as one error | The procedure on [Lengths and allocation](lengths.md) |

| Code | When |
| --- | --- |
| `FRAME` | Magic, version, flags, or a reserved byte |
| `LIMIT` | Cap, or a size product that overflows |
| `EOF` | A checked length does not fit in the buffer |
| `TYPE` | Dtype, shape, range, name, quant, or canonical-layout fault |
| `UTF8` | A name or a layout name |
| `TRAILING` | A standalone buffer continues past the value |
| `SCHEMA` | A frame hash does not match the destination type |

`SCHEMA` is the frame error for a hash that does not match the destination type.
