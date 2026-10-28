# Changes from the previous draft

This page records the corrections that version 2 made explicit. It is the changelog. The rules themselves are the earlier chapters. Read those first.

Version 2 is the first tensor layout. There is no version 1 to accept. Two correctness rules apply to Frozen values as well as to the directory, and a third rule separates the library's old 16 MiB ceiling from the wire, because a tensor length is a `u64`.

## Why these corrections were written down

The corrections exist because an earlier draft left three decisions in a state where two careful readers could implement them differently. A list of numbers was checked against the remaining bytes. A list of structs was not, and a reader could reserve up to the cap after seeing only the count. Byte order was assumed to be the host's order, which is little-endian on the machines used to test and is not a specification. A single 16 MiB ceiling was doing two jobs: limiting a string, and sounding like a wire maximum. A tensor payload is a `u64`. That ceiling could not be both.

The alternative was to leave the draft and let the tests imply the rule. Tests imply whatever the current code does. The next port then copies the accident. Writing the three rules into the normative text, and pinning them with cases, makes the accident illegal. Allocation before use is `EOF` or `LIMIT` as the procedure says, for lists of numbers, strings, structs, and for a tensor count. Little-endian is required on every host. A refusal to byte-swap is conforming. Writing host order and calling it Kiln is not. The cap is the library's. The wire maximum of a `u32` count remains 4,294,967,295.

This is a good decision because the directory work was the moment those holes would have spread. A new block with a `u64` length inherits a muddy 16 MiB rule unless the muddy rule is split first. The cost is that version 2 is stricter than a reader of the old draft might have hoped. There is still no version-1 directory to accept. A program that allocated from a struct count and called that Kiln was already outside the intent. It is now outside the text.

Analogy. A lab manual gets a correction slip at the back when a procedure was ambiguous enough that two students set the apparatus up differently. The slip does not add a new experiment. It says which of the two setups was the experiment. These three corrections are that slip. The procedures they correct are the earlier chapters.

The summary is the table. The wording that was already normative follows it.

| Correction | What it makes explicit | The case that pins it |
| --- | --- | --- |
| Allocation before a count may reserve storage | A list of structs or strings uses the same minimum-size check as a list of numbers | `kiln-list-struct-hostile`, `kiln-list-struct-short`, `kiln-list-str-short`, `kiln-pod-list-short`, `kiln-v2-directory-eof`, `kiln-v2-count-cap`, `kiln-v2-payload-overflow` |
| Little-endian on every host | Host byte order is conforming only when it matches the wire | `kiln-v2-f32`, `kiln-v2-f32-negzero`, `kiln-v2-f64-nan`, `kiln-pod-list-f32`, `kiln-v2-le-clear` |
| A cap distinct from the wire maximum | A `u32` count may be as large as 4,294,967,295 on the wire, and a library may refuse earlier with [`LIMIT`](glossary.md#limit) | The Mojo default cap is 16,777,216 |

## Corrections in this version

Two correctness rules are part of this draft, and they apply to Frozen values as well as to the new directory. A third rule splits the old 16 MiB ceiling from the wire, because a tensor length is a `u64`.

**Allocation.** Before a decoder allocates storage for a count, it requires the unread bytes to hold the minimum legal encoding of that many elements. The check covers lists of numbers, strings, and structs, and it covers a tensor count. The cases `kiln-list-struct-hostile`, `kiln-list-struct-short`, `kiln-list-str-short`, `kiln-pod-list-short`, `kiln-v2-directory-eof`, `kiln-v2-count-cap`, and `kiln-v2-payload-overflow` pin it.

**Byte order.** Every multi-byte integer and every multi-byte numeric payload is little-endian on every host. Copying host memory into the wire image is conforming only when the host is little-endian and the host type has the same width and order as the wire type. On any other host the implementation byte-swaps, or it refuses the operation before it writes. A refusal is conforming. Writing host byte order and calling the result Kiln is not. The cases `kiln-v2-f32`, `kiln-v2-f32-negzero`, `kiln-v2-f64-nan`, `kiln-pod-list-f32`, and `kiln-v2-le-clear` pin the byte patterns and the flag.

**Limits.** A Frozen `u32` length or count has wire maximum 4,294,967,295. An implementation has a configurable cap at or below that maximum. The Mojo default is 16,777,216 counts and 16 MiB for one string or byte run until a caller raises it. A value above the cap is `LIMIT`. A value inside the cap that does not fit in the buffer is `EOF`. A tensor payload length is a `u64`. The count cap does not apply to a payload returned as a view of a buffer the caller already holds. An owned copy may refuse a payload above the configured byte cap with `LIMIT`, after the block has been checked to fit.
