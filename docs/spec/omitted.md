# What this version leaves out

An omission in this version is a job the byte rules do not do. The list is part of the specification so a reader does not search the tables for a feature that was considered and left out.

This chapter answers which jobs those are, what each one would have cost, and which existing format still does the job.

## Why the omissions are part of the specification

The omissions are part of the specification because a reader who has used other formats will look for their features here, and silence looks like an oversight. Schema evolution, column scans, compression, dequantization, and a device pointer are reasonable features. Each one conflicts with a property this version states. A tag on every field conflicts with a positional record. A column layout conflicts with one encoder. A compression wrapper conflicts with "the payload is the array" unless the wrapper is outside the value. Dequantization conflicts with returning the bits the writer stored. A GPU pointer names memory that is not in the buffer, so a file would stop being a sequence of bytes.

The alternative is to leave these for a later page that never arrives, and to let each port invent a different answer. One port would skip unknown fields. Another would gzip the buffer and still call it Kiln. A third would dequantize `e2m1` on read. The files would not match, and each port would be locally reasonable. Writing the refusal down makes the locally reasonable choice non-conforming. Case `kiln-v2-bad-version` is the small version of the same idea: directory version 1 is `FRAME`, because there is no earlier tensor layout to be kind to.

This is a good decision if the boundary stays visible. Frozen and the version-2 directory are the layouts an encoder writes. The other jobs have formats that already do them well, named in the table below. The cost is a reader who wanted one library to be JSON, Protobuf, Parquet, and a quantizer. That reader will not be satisfied, and the book would be worse if it pretended otherwise. A borrowed CPU view is the interchange a later DLPack export would use. The export is an API. It is not a wire rule, and saying so here is what keeps a pointer width out of the directory.

Analogy. A road map that draws only the roads it maintains, and marks the others as someone else's, saves a traveler from searching for a junction that was never built. The unmarked junction is not a secret. It is a road this map refuses to invent.

The jobs are schema evolution, a columnar scan, compression, dequantization, and a GPU pointer. Case `kiln-v2-bad-version` is the refusal of an earlier directory: the version byte is 1, and the reader returns [`FRAME`](glossary.md#error-frame). There is no version-1 tensor layout to accept.

| Left out | The job | Why it is absent | Where that job still lives |
| --- | --- | --- | --- |
| A tag on each field | An old reader skips a field a new writer added | The tag is the per-value cost [Frozen](frozen.md) is specified to avoid | Protocol Buffers |
| Profile code 4, Columns | Read one field from many records and skip the rest | A second layout. Experiment E11 on the [experiments](../experiments.md) page left it unshipped | Arrow and Parquet |
| A compression wrapper | Fewer bytes for a large payload | On the i7-12800H runs recorded on the experiments page (powersave governor, one pinned core, 2026-10-16 and 2026-10-17), experiment E14 did not add one. The Frozen message is 37 bytes, and compressing a message that small costs more than it saves | A compressor the caller applies to a finished buffer |
| Dequantization | Multiply a scale into the elements while reading | The payload would stop being the stored bits | The caller, after [Quantization](quantization.md) checks the counts |
| A GPU pointer, or a DLPack export | Name device memory in the file | The wire would point at memory that is not in the buffer | A borrowed CPU [view](glossary.md#view). A later export would start from that view. The export is an API, not a wire rule |

The table is the explanation. The two paragraphs that follow are the normative list.

## Not in this version

This version does not add a columnar profile, a compression wrapper, or per-field evolution tags. It does not dequantize. It does not define a GPU pointer. A borrowed CPU view of a payload is the interchange a later DLPack export would use. The export itself is an API, not a wire rule.

A directory version other than 2 is rejected. A longer string or list is accepted when the caller raises the library cap.
