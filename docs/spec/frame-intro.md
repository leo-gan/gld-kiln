# The frame

A [frame](glossary.md#frame) is sixteen bytes written in front of one Frozen value, and those bytes carry a hash of the type. The frame exists so a reader can stop before the first field when the buffer was produced from a different struct.

## Why a mismatch is a stop, not a repair

A mismatch is a stop because a positional record has no safe repair. If the writer's struct gained a field, the extra bytes sit where the reader expects the next value, or they sit past the end. Skipping them requires a length or a tag the layout refused to spend. The hash is how the reader notices before it assigns 9 to the wrong field. Case `kiln-v2-framed` puts that hash in the first sixteen bytes. The value, including an empty directory, follows only if the hash matches the type the reader was given.

The alternative is a version integer the programmer bumps by hand. It works when every incompatible edit bumps it, and it fails when someone reorders two fields and ships the old integer. Another alternative is to carry enough of the schema to skip unknown fields, which is Protobuf. That alternative repairs the mismatch by ignoring what it does not know. Kiln's readers are built to know. Ignoring a field would mean accepting a struct they were not built from. A third alternative is to hash the tensor shapes into the frame. A different shape would then fail the frame. Kiln does not, because a shape is data. The same struct can hold a directory of two floats or of two thousand. A wrong dtype inside the directory is `TYPE`, found by the directory checks, not by the seal.

This is a good decision for a file that moves between builds of one program. The check is a compare. The failure is `SCHEMA`, which is not `TYPE` and not `EOF`. The cost is that the frame will not open an old file with a new field and do something sensible. Sensible, here, would be a guess. [What this version leaves out](omitted.md) is the chapter that says the guess was declined. Leave the frame off only when the caller already holds both the bytes and the type, and a wrong type is impossible rather than merely unlikely.

Analogy. A wax seal shows which edition of the handbook closed the envelope. Breaking a seal from another edition means you do not read the letter as if it were yours. The seal does not contain a footnote that translates the old edition into the new one. Translation is a program that knows both editions. It is not a byte in the frame.

This chapter answers what the hash covers, and what a mismatch does not repair.

Case `kiln-v2-framed` is the type `struct{id:i64,batch:tensors,}` with `id` equal to 7 and an empty directory. The hash of that type text is `0xe58aadc7552f0d82`. The case is 88 bytes. It begins with the sixteen frame bytes taken from the case hex:

```text
4b 4c 4e 30 00 00 00 00 82 0d 2f 55 c7 ad 8a e5
```

`4b 4c 4e 30` is the ASCII magic `KLN0`. The next four bytes are the Frozen profile, the flags, and the reserved byte, all zero. The last eight bytes are the hash in little-endian order. After the frame, the case holds the `i64` value 7 and the 64-byte empty directory from case `kiln-v2-empty`.

The hash is FNV-1a 64 of the canonical type text. It mixes the token `tensors`. It does not mix the dtypes or the shapes inside the directory, because those are data. The offset basis, the prime, and the token rules are [Schema hash](schema-hash.md).

If the hash does not match the type the reader was given, the reader returns [`SCHEMA`](glossary.md#error-schema) and does not read the first field. The frame holds no map from an older struct to a newer one. A changed struct fails the check. [What this version leaves out](omitted.md) says why a tag on every field was not added to avoid that failure.

| Choice | What it makes cheap | What it makes impossible | What still does that job |
| --- | --- | --- | --- |
| One hash in front of the value | A mismatched struct is rejected before any field is read | Reading a file that a newer struct extended with a field | Protobuf's field numbers and its rule for skipping an unknown field |
| The hash covers the type text, not the shapes inside a directory | Two different shapes of the same struct type still match | Catching a wrong dtype by the frame alone | The directory checks, which return [`TYPE`](glossary.md#type) |
