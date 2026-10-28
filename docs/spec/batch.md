# A batch of records

A batch is a list whose element is a struct, or the same struct written on successive calls. On the wire the batch is that list: a count, then the records in order. Reusing the caller's buffer across calls is an interface choice. It is not a field in the bytes.

This chapter answers why a repeated record makes a per-field cost matter, and why this version does not turn the batch into columns.

## Why a batch stays a list of records

A batch stays a list of records because that is the repetition a training loop and a log already have: the same struct, many times. The wire does not need a new idea for it. It needs the per-record idea to stay cheap, because a cost per field is now a cost per field per record. One hundred copies of `spec/golden/point.kiln` are a four-byte count and 800 bytes of integers. The names `x` and `y` do not appear in those 800 bytes. A JSON array of one hundred objects writes both names on every copy. A tagged format branches on a field number on every copy.

The alternative that looks attractive at this scale is columns. Store every `x` together and every `y` together, and a reader that wants only `x` skips `y`. Arrow and Parquet are that design, and they are the right design for a scan. They are a second layout: a footer, column chunks, and a different encoder. Profile 4 names that layout and this version does not ship it. Experiment E11 on the [experiments](../experiments.md) page left it unshipped. A list of fixed-width numbers is already one contiguous run, which is [a numeric array](array.md). A list of structs is not rewritten into columns in order to make the batch look modern.

Reusing the caller's buffer across encodes is not part of the batch's bytes. It is how a library avoids allocating a fresh buffer per record. The specification mentions it so the interface is not confused with the wire. Two encoders that reuse or do not reuse still produce the same list if they write the same records.

This is a good decision for the batch Kiln is for: many small records of a shared struct, read and written as records. The advantage grows with the count, which is why a single `Point` understates the format. The cost is a reader that wants one column. That reader either scans the records and ignores the other fields, or it uses a columnar format. Both are reasonable. Only the first is Kiln.

Analogy. A tray of identical envelopes goes to one office. Printing the office name on every envelope repeats a fact the tray already has. The tray is the list. The envelope is the struct. A sorter that wants only the postcode from every envelope is a column scan. This version ships the tray.

The list uses the allocation check in [Lists and a count that must fit](lists.md). Each element uses the [Frozen](frozen.md) layout of its struct. A batch does not add a profile of its own. Profile code 4, Columns, is not in this version, so the batch is not stored as one column per field. [What this version leaves out](omitted.md) records that decision. A list of fixed-width numbers is already one contiguous run of bits. That shape is [a numeric array](array.md), not a list of structs.

The [experiments](../experiments.md) page records a batch of 100 small messages on an Intel i7-12800H, powersave governor, one pinned core, in the runs dated 2026-10-16 and 2026-10-17. Those times are measurements of one library. They are not wire rules.

| Choice | What it makes cheap | What it makes impossible | What still does that job |
| --- | --- | --- | --- |
| A list of structs in declaration order | Each record costs its fields and not a repeated name | Reading one field of every record without touching the other fields | Arrow and Parquet |
| One count for the whole list | A hostile count fails before the elements are allocated | Finding the end of a batch only by reading until the buffer ends | A concatenation of separate values with no count. Kiln's list has a count |
