# Kiln wire format, version 2

This book is the normative specification of Kiln wire format, version 2. Kiln is a positional little-endian encoding. The reader knows the type, so the bytes do not carry field names or field numbers. A tensor directory is a Frozen value. Its version is 2, and there is no earlier tensor layout.

`spec/reference/kiln_ref.py` is the reference codec for Frozen scalars, lists, and structs. The Mojo tests check the tensor directory and the allocation rule. The hex cases live in `spec/kiln-v2-cases.json`. The reference cap in those cases is 16,777,216, which is the Mojo library's default.

A definition says what a term means. The [glossary](glossary.md) is the short index. [Terminology](terminology.md) is the full definition of every term, including why the word is needed. A rule says what a conforming encoder writes and what a conforming decoder accepts or rejects, and it names the error code. An example is a byte string copied from a golden file or from a named case. An example does not override a rule.

A reader who knows JSON, and has only heard the word serialization, starts with the [repository README](https://github.com/leo-gan/gld-kiln#readme). A reader who has used two or three formats starts with [Introduction](first.md). The chapters below are the full account.

## Introduction

Each chapter answers one question.

| Chapter | Question |
| --- | --- |
| [The same record in three encodings](record.md) | What do JSON, Protocol Buffers, and Kiln put in the bytes of one struct? |
| [Schema and declaration order](schema.md) | Which order do the fields occupy, and how is a dict ordered? |
| [Widths, lengths, and byte order](widths.md) | Why does a number have a fixed width, and why is that width little-endian? |
| [Lists and a count that must fit](lists.md) | When does a count fail before any element storage is allocated? |
| [A batch of records](batch.md) | What is a repeated record on the wire? |
| [A numeric array](array.md) | When is a list of numbers enough, and when is a directory required? |
| [Names, scales, and foreign blocks](directory-intro.md) | What do the golden directories actually contain? |
| [The frame](frame-intro.md) | What does the type hash cover, and what does a mismatch refuse to repair? |
| [What this version leaves out](omitted.md) | Which jobs are specified as absent? |

## Rules

| Chapter | Question |
| --- | --- |
| [Frozen values](frozen.md) | How is each Frozen value encoded? |
| [Lengths and allocation](lengths.md) | What is the check, in order, before a count may allocate? |
| [Byte order](byte-order.md) | Which bit patterns are required? |
| [Schema hash](schema-hash.md) | How is the type hash computed? |
| [Frame](frame.md) | What are the sixteen prefix bytes? |
| [Tensor directory](tensor-directory.md) | What are the header, the descriptor, and the name heap? |
| [Check order](check-order.md) | Which fault is reported when a block has several? |
| [Dtypes](dtypes.md) | What is the closed set of element codes? |
| [Quantization](quantization.md) | How does a scale tensor relate to the data tensor? |
| [Opaque layouts](opaque.md) | What does an opaque dtype require? |
| [Canonical layout](canonical.md) | Which placement must every encoder write? |
| [Embedding](embedding.md) | Where does a directory sit inside a struct? |
| [Errors](errors.md) | What does each error code mean? |
| [Golden cases](golden.md) | Which case pins which rule? |
| [Dynamic values](dynamic.md) | Which JSON Schema subset generates a struct? |
| [What a trusted reader may skip](trusted.md) | Which checks do the fast readers omit? |
| [Profiles](profiles.md) | Which profile codes are specified? |
| [Changes from the previous draft](changes.md) | Which corrections did version 2 make explicit? |

## Earlier heading links

A link that used to end in a fragment on `/spec/` now opens the page in this table. The fragment on the new page is the heading it used to name.

| Old fragment | New page |
| --- | --- |
| `#what-kiln-guarantees` | [What Kiln guarantees](record.md#what-kiln-guarantees) |
| `#corrections-in-this-version` | [Corrections in this version](changes.md#corrections-in-this-version) |
| `#byte-order` | [Byte order](byte-order.md#byte-order) |
| `#lengths-and-allocation` | [Lengths and allocation](lengths.md#lengths-and-allocation) |
| `#profiles` | [Profiles](profiles.md#profiles) |
| `#frozen-values` | [Frozen values](frozen.md#frozen-values) |
| `#schema-hash` | [Schema hash](schema-hash.md#schema-hash) |
| `#frame` | [Frame](frame.md#frame) |
| `#tensor-directory` | [Tensor directory](tensor-directory.md#tensor-directory) |
| `#header` | [Header](tensor-directory.md#header) |
| `#sections` | [Sections](tensor-directory.md#sections) |
| `#descriptor` | [Descriptor](tensor-directory.md#descriptor) |
| `#names` | [Names](tensor-directory.md#names) |
| `#check-order` | [Check order](check-order.md#check-order) |
| `#dtypes` | [Dtypes](dtypes.md#dtypes) |
| `#quantization` | [Quantization](quantization.md#quantization) |
| `#opaque-layouts` | [Opaque layouts](opaque.md#opaque-layouts) |
| `#canonical-layout` | [Canonical layout](canonical.md#canonical-layout) |
| `#embedding` | [Embedding](embedding.md#embedding) |
| `#errors` | [Errors](errors.md#errors) |
| `#golden-cases` | [Golden cases](golden.md#golden-cases) |
| `#not-in-this-version` | [Not in this version](omitted.md#not-in-this-version) |
| `#dynamic-values` | [Dynamic values](dynamic.md#dynamic-values) |
| `#what-a-trusted-reader-may-skip` | [What a trusted reader may skip](trusted.md#what-a-trusted-reader-may-skip) |
