# What a trusted reader may skip {#what-a-trusted-reader-may-skip}

A trusted reader is a decode path that skips bounds checks because the caller already knows the buffer's length. It exists for a buffer this process has just encoded. It is not the path for a file from outside the process.

`decode` checks bounds, UTF-8, and the tensor-directory rules. `Reader.u8_fast`, `u32_fast`, `u64_fast`, and `str_fast` do not check bounds. A hostile length passed to `str_fast` can read off the end of the span. That sentence is the rule. The fast readers are an API. They do not define a second wire layout.

## Why an unchecked reader exists

An unchecked reader exists because the checks in `decode` are the right default and the wrong cost on a buffer this process has just written. The writer already knew the lengths. Reading them back with the same checks pays for a hostile file that this buffer is not. `u8_fast`, `u32_fast`, `u64_fast`, and `str_fast` skip the bounds test. They do not define a second layout. The bytes are still Frozen bytes.

The alternative is to check every time. That alternative is safer, and it is what `decode` does. A library that offered only the fast path would be faster on the benchmark and wrong on a file. A library that offered only the checked path would be easier to explain and would leave the measured batch slower than it needs to be for bytes the caller trusts. Kiln offers both and writes down which one may read off the end of a span. The sentence is not a footnote. A hostile length passed to `str_fast` can read past the buffer. That is a memory error, not a `Kiln` error code.

This is a good decision if the names stay honest. "Fast" means "the caller promises the length." It does not mean "try this first." The checked decode remains the function a file should go through, including UTF-8 and the directory rules. The cost of the split is a second API that will be misused if a sample copied from a benchmark is pointed at the network. The specification says so here so the misuse is a broken promise, not an ambiguity.

Analogy. A cook may skip re-reading a recipe they wrote down a moment ago. The same cook reads a recipe found on the street from the first line. The street recipe is `decode`. The recipe just written is the fast reader. Skipping the street recipe is how a kitchen gets poisoned.

| Choice | What it makes cheap | What it makes impossible | What still does that job |
| --- | --- | --- | --- |
| An unchecked reader beside `decode` | A buffer just written can be reread without repeating checks the writer already satisfied | Feeding an untrusted file to `str_fast` safely | `decode`, which checks |

`decode` checks bounds, UTF-8, and the tensor-directory rules. `Reader.u8_fast`, `u32_fast`, `u64_fast`, and `str_fast` do not check bounds. They are for a buffer this process just encoded, or another buffer whose length was already checked. A hostile length passed to `str_fast` can read off the end of the span.
