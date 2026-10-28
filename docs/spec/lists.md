# Lists and a count that must fit

A list on the wire is a count followed by that many elements. Kiln checks the count against the bytes still unread before it allocates storage for the elements. A count is a claim. It is not evidence that the elements are present.

This chapter answers how a hostile count is rejected, and which of [`EOF`](glossary.md#eof) or [`LIMIT`](glossary.md#limit) that rejection uses.

Case `kiln-pod-list-f32` is a list that fits. The bytes are `02 00 00 00 00 00 80 3f 00 00 00 c0`: the count 2, then the 32-bit values 1.0 and −2.0. The minimum size of one `f32` is 4 bytes. Eight bytes remain after the count, so the reader may allocate the two elements.

Case `kiln-pod-list-short` uses the same element type, the count 2, and only four payload bytes. Two elements need eight bytes. The reader returns `EOF` and does not allocate the list. Case `kiln-list-struct-hostile` sets the count to the default cap, 16,777,216, and supplies no elements. The element minimum in that case is 8 bytes, so the product does not fit in the unread bytes. The error is `EOF`, not `LIMIT`, because the count itself is inside the cap. `LIMIT` is the error when the count is above the cap, or when `count` times the minimum size overflows an unsigned 64-bit integer. Case `kiln-v2-count-cap` is the directory form of a count above the cap: 16,777,217 tensors, error `LIMIT`.

## Why the count is checked before any allocation

The count is checked first because it is the cheapest place a hostile or truncated buffer can lie, and the most expensive place to believe the lie. Reserving one slot per claimed element, and only then discovering the bytes are absent, is how a short file becomes a large allocation. Kiln multiplies the count by the schema's minimum size and demands that the product fit in the unread bytes and in a 64-bit integer. The cases above are the three outcomes. `kiln-pod-list-f32` fits. `kiln-pod-list-short` is `EOF` and allocates nothing. `kiln-list-struct-hostile` is also `EOF`, not `LIMIT`, because 16,777,216 is inside the default cap and the elements are still absent. `kiln-v2-count-cap` is the directory whose count is past the cap, and that one is `LIMIT`.

The alternative is to grow the list while parsing and stop at the end of the buffer. Callers then cannot tell a short file from a short list. Another alternative is to allocate the cap and ignore the count when the buffer is small. That caps the damage and still does work proportional to a number the file should not have been allowed to name. Kiln fails before that work. The check uses the minimum, so it does not need the elements in order to know they cannot all be present. An element that passes the minimum may still be longer. A string's body is checked again when that string is read. The list rule does not replace the element rule. It stops the count from reserving the slots.

This is a good decision for a decoder that will see files it did not write. The failure is early, it is named, and it does not depend on how much memory the machine has today. The cost is that a truncated file is an error rather than a partial success. A caller who wants a prefix slices the buffer to the prefix and decodes that. The precise five steps are [Lengths and allocation](lengths.md).

Analogy. A packing slip that claims more boxes than the parcel can hold is refused before anyone reserves a shelf per claimed box. The shelf is the allocation. The slip is the count. Measuring the parcel is the minimum-size product. You do not rent the warehouse and then count the boxes.

| Choice | What it makes cheap | What it makes impossible | What still does that job |
| --- | --- | --- | --- |
| Require `count * minimum` to fit before allocating | A lying count cannot reserve one slot per claimed element | Returning a short list from a truncated buffer | A parser that fills what it can and stops. Kiln returns `EOF` |
| A configurable [cap](glossary.md#cap) under the wire maximum | One library can refuse a count it is not prepared to allocate | Forcing every implementation to allocate up to 4,294,967,295 elements | The wire still allows a `u32` count that large. The Mojo default cap is 16,777,216 |
