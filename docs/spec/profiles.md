# Profiles {#profiles}

A profile is a named layout identified by a small integer in a frame. The integer exists so a reader can tell which layout follows the frame without guessing.

This page answers which codes this version actually specifies. [What this version leaves out](omitted.md) explains the codes that are not the default.

## Why a profile exists

A profile is a small integer that names which layout follows a frame. Kiln had several layouts it might have specified: a frozen record, a record that can grow a new field, a borrowed view stored with its own offsets, a tensor file, and a columnar table. If those layouts shared one header and no code, a reader would have to guess which bytes came next. The profile code is that guess, written down.

The alternative is one layout for every job, or a file that carries its own schema so no code is required. JSON takes the second road. There is no profile, because every value describes itself with names. Protobuf stays with one tagged layout, and the field number does the job a profile would otherwise do. FlatBuffers and Cap'n Proto each pick an offset layout and stay there. Arrow picks columns and stays there. Kiln's job is narrower and it is two jobs at once: a struct both programs already share, and numeric arrays inside that struct. Those two shapes are different. Evolution and column scans are different again. A profile number reserves a slot for each shape, so an experiment can be recorded without becoming the default and without quietly reusing Frozen's number.

Kiln creates profile 0, Frozen, as the layout an encoder writes. The tensor directory is not profile 3 in the frame. It is a Frozen value whose canonical name is `tensors`, and the directory's own version byte is 2. That split is the design. A frame answers which record layout this is. A directory header answers which tensor block this is. Folding both answers into one byte would make every small message carry tensor machinery, and it would make every tensor block pretend to be a whole file. Case `kiln-v2-framed` shows the split in bytes: the frame profile is 0, and the directory inside the value has its own magic.

This is a good decision for programs that share a struct. The default can be the layout that writes values and not names, because the names are already in the source. The other codes stay in the table so a later writer cannot claim that "we always used 1 for something else." Code 1, Evolve, would put a length or a tag on fields so an old reader could skip a new field. That feature is real, and it is the per-value cost Frozen is specified to remove. Code 4, Columns, would store one field of many records together. Arrow and Parquet already do that, with a footer and a column chunk. Shipping it here would mean a second encoder before the first layout was finished. Code 2, View, names a borrowed read. The read is useful. It does not need its own bytes, because a view borrows the Frozen bytes that are already there.

Analogy. A print shop keeps one plate on the press and the other plates in a numbered rack. The number does not print the page. It stops the operator from inking the wrong plate. Frozen is the plate on the press. The profile table is the rack. An unnumbered extra plate would eventually be inked by mistake.

The advantage is a single default that matches the shared-struct job, a visible place for experiments that are not the default, and a tensor block that versions itself. The cost is honest. A file written under a future Evolve profile will not be read by a Frozen decoder. There is no column scan in this version. A borrowed view is an API choice, not a bit the profile byte turns on.

The directory a tensor chapter describes is not a separate frame profile. It is the Frozen value whose canonical name is `tensors`. The frame profile in case `kiln-v2-framed` is 0.

| Code | What shipping it makes cheap | What leaving it out makes impossible | What still does that job |
| --- | --- | --- | --- |
| 0 Frozen | The default path has one layout | Nothing further. This code is the default | This book |
| 1 Evolve | An experiment can try field evolution without becoming the default | Old files that grow a field and stay readable | Protocol Buffers |
| 2 View | A name for a borrowed read | A second layout beside Frozen | The borrowed read uses the Frozen bytes |
| 3 Tensor, as the value `tensors` | Arrays and a struct share one buffer | A tensor layout with a version byte other than 2 | None in this version. Another version is [`FRAME`](glossary.md#error-frame) |
| 4 Columns | A scan of one field across many records | That scan, inside Kiln | Arrow and Parquet |

The directory is a Frozen value, not a separate frame profile.

| Code | Name | Status |
| --- | --- | --- |
| 0 | Frozen | Normative. This is the default. |
| 1 | Evolve | Still an experiment. Not the default API. |
| 2 | View | Still not a separate layout. A borrowed read uses the Frozen bytes. |
| 3 | Tensor | The Frozen value `tensors`. The directory version byte is 2. |
| 4 | Columns | Not in this version. |
