# Schema and declaration order

The [schema](glossary.md#schema) of a Kiln value is the struct's fields, their types, and the order of those fields in the source. That order is the encoding. Writing the names again would repeat a fact both programs were compiled with.

This chapter answers which order the bytes follow, and what a dict does when the source has no single field order.

[`Point`](record.md) declares `x` and then `y`. Kiln writes `x` and then `y`. The bytes `09 00 00 00 fc ff ff ff` in `spec/golden/point.kiln` are 9 and then −4. If the source declared `y` first, the same numbers would occupy `fc ff ff ff 09 00 00 00`. The values would be the same and the byte string would not. [The frame](frame.md) hashes the type text, so a reader built from the other declaration stops with [`SCHEMA`](glossary.md#error-schema) before the first field.

## Why the source order is the wire order

The source order is the wire order because it is the one order both programs already agreed to by compiling. Any other order needs a signal in the bytes to say which field this is. That signal is a name or a number. Kiln's struct does not carry it. Swapping `x` and `y` in the source swaps the eight bytes of `spec/golden/point.kiln` from `09 00 00 00 fc ff ff ff` to `fc ff ff ff 09 00 00 00`. The values are the same pair. The file is not the same file. [The frame](frame.md) hashes the type text so the reader built from the other order fails with `SCHEMA` instead of quietly swapping the numbers.

A dict has no source order. Leaving the writer's insertion order in the file would make two encoders of the same pairs disagree, and "the same value has the same bytes" would depend on a hash table. Kiln sorts keys by their UTF-8 bytes, lexicographically, the same way it needs one order everywhere else. The alternative is to forbid dicts and make the caller pass a list of pairs. A list keeps insertion order, and it is the right tool when that order is data. A dict whose order is not data gets the sort. The sort is specified with [Frozen values](frozen.md), together with the rule that nothing is padded between fields.

This is a good decision because a struct then has one obvious encoding, the one you see when you read the source from top to bottom. The cost is that the wire is not a place to discover fields, and a dict will not round-trip the order a JSON object happened to use. If the order of keys matters, put them in a list. If a reader must accept a field it was not compiled with, put a field number in front of the value and stop using this layout.

Analogy. A filing cabinet that both offices bought from the same list has a drawer order. Letters go in that drawer order. A pile of loose mail, which is a dict, gets sorted by address before it is filed, so two clerks produce one cabinet. The cabinet does not remember which letter was dropped on top.

| Choice | What it makes cheap | What it makes impossible | What still does that job |
| --- | --- | --- | --- |
| Declaration order | One store per field, with no name and no tag | Inserting a field that an old reader skips | Protobuf's field numbers |
| Sorted dict keys | One [canonical](glossary.md#canonical) byte string for one set of pairs | Preserving the order in which the caller inserted the keys | A list of pairs, which keeps the caller's order |

The handbook picture for this choice is in [the record chapter](record.md). The precise rule is narrower than that picture. Struct fields are written in source order. Dict keys are written in lexicographic order of their UTF-8 bytes. Frozen inserts no padding between fields.
