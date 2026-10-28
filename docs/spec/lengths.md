# Lengths and allocation {#lengths-and-allocation}

A length check is the test a reader applies to a count before it allocates storage for that many elements. The test exists so a count larger than the remaining bytes cannot reserve a slot per claimed element.

This page is the procedure. [Lists and a count that must fit](lists.md) explains the cases. Case `kiln-pod-list-f32` is the list that fits: `02 00 00 00 00 00 80 3f 00 00 00 c0`.

The errors in the procedure are [`EOF`](glossary.md#eof) when the count word or the minimum bytes do not fit, and [`LIMIT`](glossary.md#limit) when the count is above the [cap](glossary.md#cap) or a product overflows.

## Why the check exists

The check exists because a count is untrusted input. A file, a socket, or a bug can say that a list contains millions of elements and then end. A reader that allocates first and looks second will reserve that storage, or it will overflow the multiplication and reserve a wrapped size. Kiln requires the unread bytes to hold the minimum legal encoding of the claimed elements, and it requires the product to fit in an unsigned 64-bit integer, before it allocates.

The alternative is to trust the writer. That alternative is reasonable for a buffer this process just encoded, which is why a trusted reader exists, and it is a bad default for a buffer from outside the process. Another alternative is to allocate a small chunk, parse until the buffer ends, and return a short list. That is a friendly parser. It is also a parser that turns a truncated file into a successful decode. Kiln treats truncation as `EOF`. A third alternative is one maximum for every implementation, equal to the wire maximum of a `u32`. The wire allows 4,294,967,295. Forcing every library to be ready to allocate that many slots would make the safe implementation the one that refuses. The cap makes the refusal a named error, `LIMIT`, distinct from a short buffer.

Kiln creates the five-step order so two decoders fail the same way. The count word itself must fit. The count must be within the cap. The product `count * m` must not overflow. The product must fit in the unread bytes. Only then may the reader allocate. A later element may still be longer than the minimum. That later failure belongs to the element. The same idea bounds a tensor directory: the reader does not allocate one descriptor per claimed tensor until `tensor_count * 128 + name_bytes` lies inside the buffer. It does not allocate a payload in order to discover that the block does not fit.

This is a good decision for a format that will be pointed at files it did not write. The minimum size comes from the schema, so the check does not need to parse the elements to know they cannot all be present. Case `kiln-pod-list-f32` is the list that passes. Case `kiln-pod-list-short` is the list that must not allocate. Case `kiln-list-struct-hostile` shows the cap and `EOF` are different: a count of 16,777,216 with no elements is inside the default cap and still does not fit, so the error is `EOF`. The cost is that a truncated-but-almost-valid buffer is rejected rather than repaired. A caller that wants the prefix must slice it before it calls decode.

Analogy. A warehouse door measures the truck against the bay before it opens the bay. A packing slip that claims more boxes than the truck can hold does not cause the warehouse to rent a shelf per claimed box. The measurement is the minimum size. The bay is the unread buffer.

| Choice | What it makes cheap | What it makes impossible | What still does that job |
| --- | --- | --- | --- |
| Minimum size times count, before any allocation | The failure does not depend on parsing every element first | Accepting a short buffer as a shorter list | A streaming parser that returns what it could read |
| A view that borrows the caller's buffer | A payload the caller already holds is not copied in order to discover that it fits | An owned copy of a payload above the configured byte cap | The caller raises the cap, or keeps the view |

The reader consumes the count, then applies this check, then allocates.

1. If the count word itself does not fit, the error is `EOF`.
2. If the count is above the configured cap, the error is `LIMIT`. The default cap is 16,777,216. The check happens before any allocation whose size depends on the count.
3. Let `m` be the minimum wire size of one element, from the table below. If `m` is greater than 0 and `count * m` does not fit in an unsigned 64-bit integer, the error is `LIMIT`.
4. If `count * m` is greater than the number of unread bytes, the error is `EOF`. The reader does not allocate element storage.
5. Only a count that passes these steps may allocate. A later element may still be longer than the minimum and may then fail. That later failure is the element's own error.

| Element | Minimum bytes |
| --- | --- |
| `bool`, `i8`, `u8` | 1 |
| `i16`, `u16` | 2 |
| `i32`, `u32`, `f32` | 4 |
| `i64`, `u64`, `int`, `uint`, `f64` | 8 |
| `str`, `list<u8>` | 4 |
| `opt<T>` | 1 |
| `list<T>`, `dict<str,V>` | 4 |
| `tensors` | 64 |
| struct | Sum of the field minimums |

A struct with no fields has minimum 0. The product is then 0, so the byte check does not reject the count. The cap in step 2 is what bounds that allocation.

A string length is still checked against the unread bytes before the string body is allocated. The list rule is in addition to that check. It stops a count from reserving a slot per element when those elements cannot all be present.

The same idea bounds a tensor directory. The reader does not allocate one descriptor per claimed tensor until `tensor_count * 128 + name_bytes` lies inside the buffer, the product does not overflow, and `tensor_count` is within the cap. It does not allocate a payload of `payload_bytes` in order to decide that the block does not fit. A view borrows the caller's buffer. An owned copy allocates the payload only after the block end has been checked.

`payload_base + payload_bytes` is computed in unsigned 64-bit arithmetic. If the sum overflows, the error is `LIMIT`.
