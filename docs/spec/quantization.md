# Quantization {#quantization}

Quantization metadata is a pair of indexes from a data tensor to other tensors in the same directory. The indexes exist so a scale can be stored beside the elements without changing those elements.

[Names, scales, and foreign blocks](directory-intro.md) shows cases `kiln-v2-scales` and `kiln-v2-scales-outer`. This page is the rule those cases pin. The reader does not multiply. A wrong group count is [`TYPE`](glossary.md#type), case `kiln-v2-scale-count`. A chain, where the scale tensor itself has a scheme, is `TYPE`.

## Why the scale is another tensor

The scale is another tensor because a quantized block is still bits plus a description, and Kiln already has a way to store bits plus a description. Inventing a second layout for scales would mean a second length check and a second alignment rule. Pointing at a sibling reuses both. Scheme 0 is no link. Scheme 1 is one scale tensor. Scheme 2 adds one outer `f32` with a single element. The reader checks the counts. The reader does not multiply.

The alternative is to dequantize while reading, and to hand the caller a buffer of `f32`. That is convenient and it destroys the property that the payload is the array. It also freezes a rounding policy into the decoder. Another alternative is ggml's approach: the block layout is interpreted, and the scale lives in a tiled arrangement the format defines byte by byte. That is the right design for a runtime that must compute. It is a large surface for a format whose other job is a struct. A third alternative is to store the scale in the descriptor itself, as a single float. That covers a tensor-level scale and does not cover a scale per group of 32.

Kiln leaves the element dtype of the scale unset by the scheme, except that scheme 2's outer tensor is `f32`. Case `kiln-v2-scales` uses `e2m1` elements and one `e8m0` byte of value 127, the shape of an MXFP4 block of 32. Case `kiln-v2-scales-outer` is 16 `e2m1` elements, one `f8e4m3` scale, and one `f32` outer value. The group formula is `ceil(shape[axis] / group_size)` times the product of the other dimensions. A mismatch is `TYPE`, case `kiln-v2-scale-count`. A scale that itself has a scheme is a chain, and a chain is `TYPE`, because a chain has no end the checker can see from the two indexes.

This is a good decision for a file that must move weights without becoming an evaluator. The bits a writer stored are the bits a reader returns. The group count is still policed, so a truncated scale is not a successful read. The cost is that a caller who wants floats must multiply, and must bring the numeric rules for `e2m1` and `e8m0` from the OCP specification. Kiln cites those bit layouts and does not restate the arithmetic.

Analogy. A map and its legend are stored in the same folder. The legend says how to read a color. The clerk checks that the legend has an entry for each band the map claims. The clerk does not repaint the map. Repainting is the caller's job, after the check.

| Choice | What it makes cheap | What it makes impossible | What still does that job |
| --- | --- | --- | --- |
| Scheme 1 names one sibling scale | The group count is checked and the bits are copied | A tiled scale layout with its own rules | The caller's layout, outside this version |
| Scheme 2 adds one outer `f32` of one element | A tensor-level scale sits in the same directory | An outer scale of some other dtype | Scheme 0 on that outer tensor, which must be `f32` |

Quantization metadata names other tensors. It does not change element bits, and the reader does not apply a scale.

| Scheme | Name | Rule |
| --- | --- | --- |
| 0 | none | `group_size` is 0, `quant_axis` is `0xFFFF`, and both indexes are `0xFFFFFFFF` |
| 1 | scales | One sibling holds the block scales |
| 2 | scales and outer | Scheme 1, plus one outer `f32` tensor with element count 1 |

For scheme 1 or 2 the rank is at least 1, `quant_axis` is less than the rank, and `group_size` is at least 1. The scale index points at a different tensor in this directory. That tensor uses scheme 0. Its element count equals

```text
ceil(shape[axis] / group_size) * product(shape[i] for i != axis)
```

The product of no dimensions is 1. A rank-1 tensor of 32 elements with group size 32 needs one scale. The scale tensor's dtype is not fixed by the scheme. The case `kiln-v2-scales` uses `e2m1` elements and one `e8m0` byte of value 127, which is the MXFP4 block of 32. Kiln checks the count and stores the byte.

Scheme 2 adds `outer_index`, distinct from the data tensor and the scale tensor. The outer tensor is `f32`, scheme 0, and has one element. The case `kiln-v2-scales-outer` is 16 `e2m1` elements, one `f8e4m3` scale byte, and one `f32` outer value. That is the shape of a 16-element block with an 8-bit scale and a tensor-level `f32` scale. The file stores the three tensors. It does not store a tiled scale layout.

A scale tensor does not itself carry a scheme. Chains are `TYPE`.
