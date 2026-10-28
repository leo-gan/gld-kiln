# Frame {#frame}

A frame is the sixteen-byte prefix defined here. [The frame](frame-intro.md) explains why it is a seal on the type rather than a migration guide.

Case `kiln-v2-framed` begins `4b 4c 4e 30 00 00 00 00 82 0d 2f 55 c7 ad 8a e5`. The magic is `KLN0`. The profile byte is 0. A `tensors` field may appear in the one Frozen value that follows.

A hash that does not match the destination type is [`SCHEMA`](glossary.md#error-schema).

## Why the frame exists

The frame exists to put the schema hash where a reader will see it before the value, in a fixed sixteen bytes, with a magic that rejects a buffer that is not Kiln. Without a frame, a Frozen value is still well defined. `spec/golden/point.kiln` has no frame, and it is eight bytes of integers. The frame is the choice a caller makes when a mismatch must fail closed.

The alternative is to rely on the caller to remember which struct produced the file. That works inside one process and fails at a file boundary, where the next reader is a different build. Another alternative is a textual header, long enough to hold the struct name. The header would be readable in a hex dump and expensive on a small record. Sixteen bytes is larger than `Point` and smaller than a schema document. A third alternative is Protobuf's approach: no separate seal, because every field carries a number and an unknown number can be skipped. That solves evolution. It does not solve "stop before the first field."

Kiln fixes the sixteen bytes as magic `KLN0`, profile 0, flags 0, a reserved zero, and the hash. One Frozen value follows. A `tensors` field may appear in that value. Several top-level values do not. A batch is a list inside the one value, not a sequence of frames. The magic is four ASCII bytes so a wrong file fails as `FRAME` rather than as a wild integer. The profile byte is 0 because Evolve, View, and Columns are not layouts this frame selects.

This is a good decision when the buffer will outlive the process that wrote it. The check is one comparison. The failure mode is the one a positional format needs, because the format will not notice a wrong struct on its own. The cost is sixteen bytes on every framed value, and a hard stop instead of a best-effort read. Leave the frame off when the caller already knows the type, as the golden `Point` file does.

Analogy. The frame is the envelope. The hash is the seal on the flap. The letter inside is the Frozen value. You can hand someone the letter without an envelope when you are standing next to them. You seal the envelope when the letter will be opened by a later reader who must not assume it is their letter.

| Choice | What it makes cheap | What it makes impossible | What still does that job |
| --- | --- | --- | --- |
| Sixteen bytes, then one value | The reader either accepts the type or stops | Several values inside one frame | A list of values, as [a batch](batch.md), inside the single value |
| Profile 0 in the prefix | The default layout needs no further negotiation | Selecting Evolve, View, or Columns from this prefix in this version | [Profiles](profiles.md) |

The frame is sixteen bytes: magic `KLN0`, Frozen profile 0, flags 0, reserved 0, then the schema hash, then one Frozen value. A `tensors` field may appear in that value.
