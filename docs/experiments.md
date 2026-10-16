# Experiments

The numbers below were measured on 2026-10-16 on a 12th Gen Intel i7-12800H, Linux, `powersave` governor, `taskset -c 2`, Mojo 1.1.0. Means are of the hot loop after a short warmup. One core under `powersave` is not the published GLD dashboard, which also uses this CPU model but does not pin a core. A result here does not by itself change the dashboard rank.

Sources: `experiments/harness.mojo`, `experiments/variants.mojo`, and `experiments/E15-c-ceiling/kiln_message.c`. The message is two booleans, two `Int32`s, one `Int64`, one `Float64`, and the strings `hello` and `world` (44 bytes).

| ID | Question | Result | Decision |
| --- | --- | --- | --- |
| E00 | Is the timer floor above 100 ns? | Empty timed region median about 23–26 ns. | The microbench can see a codec faster than 166 ns. Kiln's reused `Writer` is the buffer. In the GLD runner, `Fixture.empty` skips copying five suite lists inside Kiln, CBOR, Avro, EmberJson, and BSON deserialize. |
| E01 | Is reflection as fast as hand-written stores? | Batch of 100: reflection mean about 2.8 µs, hand-written `put_*` calls about 3.4 µs. | Reflection stays the only struct codec. |
| E02 | Do per-byte bounds checks matter? | Checked fast-path reads of 100 messages: about 4.5 µs. Unchecked loads: about 0.29 µs. | `decode` stays checked. `Reader.*_fast` is the trusted path. |
| E03 | Which length prefix? | Not a full A/B. The golden message is 37 bytes with `u32` lengths. The smallest published leader cited in the design notes is 48 bytes. | `u32` stays. It also covers lists longer than 65535 without a second width. |
| E04 | Fixed width or LEB128? | One `UInt64` store mean 17 ns. A one-byte LEB128 of the value 99 mean 17 ns. The timer floor hides the difference. | Fixed width stays. A message has several integers, and a branch per integer is the cost LEB128 adds on top of a store. |
| E05 | SIMD copy for short strings? | Not faster than `memcpy` in a separate run. `put_span` uses `memcpy`. | `memcpy` stays. |
| E06 | Owned strings or views? | Owned decode of one message about 85–100 ns. View of 100 messages about 0.29 µs total after checks were removed. | Owned `decode` is the default. Views are `StringSpan` from `str_fast` or from `read_string_slice`. A second wire layout with offsets was not added. |
| E07 | One copy for `List[Float64]`? | 10,000 floats: per-element stores mean 3981 ns, bulk copy mean 1489 ns (about 2.7×). | The bulk path stays for fixed-width numbers. |
| E08 | Does `raises` show up on the happy path? | Not isolated. The 37 ns encode includes the `raises` signature and does not take the error branch. | The public API still raises `KilnError`. |
| E09 | Reorder fields, fixed block first? | Not faster than declaration order in a way that would justify a second layout. Declaration order is what the schema hash describes. | Declaration order stays. |
| E10 | Pre-size the buffer? | Dropping the size pre-pass moved a batch of 100 from about 3.0 µs to about 2.8 µs. `reserve` still grows the `Writer` when it must. | No pre-pass. The caller reuses the `Writer`. |
| E11 | Columnar batches? | Not shipped. The Frozen batch encode is the path that was measured. | No column encoder in this version. |
| E12 | UTF-8 on by default? | `decode` validates. The hot decode probe passes `False` and relies on strings that were just encoded. | Validation stays on for `decode`. Turn it off only for trusted bytes. |
| E13 | Tensor copy of 2 MB? | `write_f64` of 262,144 `Float64` values (2 MiB of payload) mean 75 µs, about 0.075 ms. A Python `bytearray` copy of 2 MB on the same machine was about 0.069 ms. | The tensor block ships. 0.075 ms is under the 0.4 ms bar, and the copy is in the same range as `memcpy`. |
| E14 | Compression? | Not measured as a wrapper. The Frozen message is 37 bytes. Compression of a message that small costs more than it saves. | No compression wrapper in this version. |
| E15 | Is Mojo within 10% of C? | C encode of the same 44-byte message, `gcc -O3`, mean about 2.3 ns (`total_ns` 233226 over 100,000 reps). Mojo reflection encode mean about 37 ns. | The bar fails. The wire layout is not the whole gap. The C compiler reduces the stores further than Mojo does. Kiln still ships, because the release bar for this version is the package, not parity with that C loop. |
| E16 | Length-prefixed structs for evolution? | Not adopted. An extra `u32` per struct adds bytes and a store on the path that is already near the timer floor. | Evolve is not the default. The frame hash detects a mismatched type. |
| E17 | Presence bitmap instead of a tag byte? | Not adopted. `Optional` is rare in the measured message, and a bitmap needs a second pass or a reserved hole. | One tag byte stays. |
| E18 | Intern repeated strings? | Not adopted for structs. Dict keys are sorted, not interned. The suite message has two distinct strings. | No interning table. |
| E19 | Delta coding for integer lists? | Not adopted. E07's bulk copy is a single memory move. Delta coding replaces that with arithmetic. | Bulk copy stays. |
| E20 | Pad small messages to 64 bytes? | Not adopted. The measured message is 44 bytes. Padding would make it larger than the leaders without removing a store. | No padding on Frozen. The tensor header is 64 bytes so the payload is aligned. |

## How to reproduce

```bash
taskset -c 2 pixi run mojo run -I src experiments/variants.mojo
gcc -O3 -o /tmp/kiln_message experiments/E15-c-ceiling/kiln_message.c
taskset -c 2 /tmp/kiln_message
```

`experiments/harness.mojo` times one message and a batch of 100. It checks that the view reader consumes every byte of the batch.
