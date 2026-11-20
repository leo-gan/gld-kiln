# Empirical Evaluation and Design Experiments

Every wire-format and implementation decision in Kiln is backed by an isolated experiment (`E00`–`E26`) retained under `experiments/`. This page documents the experimental protocol, reference workloads, measured results, design decisions, threats to validity, and reproduction commands.

---

## 1. Experimental Protocol

| Parameter | Configuration |
| --- | --- |
| **CPU** | 12th Gen Intel Core i7-12800H (x86-64, little-endian) |
| **OS & Pinning** | Linux, `powersave` CPU frequency governor, single pinned core (`taskset -c 2`) |
| **Compiler** | Mojo `1.1.0` (pinned in `pixi.toml`); C reference compiled with `gcc -O3` |
| **Measurement Dates** | Initial suite: `2026-10-16`; post-directory re-measurement (`E07`, `E13`, `E15`, `decode_small.mojo`): `2026-10-17` |
| **Timing Scope** | Hot-loop arithmetic mean (and best) over `perf_counter_ns` after warmup; `Writer` pre-allocated and reused across iterations; tensor directory constructed prior to timed loop |
| **Sources** | `experiments/decode_small.mojo`, `experiments/variants.mojo`, `experiments/mojo_speed.mojo`, `experiments/utf8_words.mojo`, `experiments/list_place.mojo`, `experiments/harness.mojo`, `experiments/E15-c-ceiling/kiln_message.c` |

### Threats to Validity

1. **Governor and pinning vs. published dashboard:** Measurements use one pinned core under `powersave` and are **not** equivalent to unpinned GLD dashboard runs on the same CPU model; local numbers do not alter published dashboard rankings.
2. **Timer floor:** An empty timed region has a median floor of ~23–26 ns (`E00`), limiting resolution for single sub-20 ns scalar operations (`E04`).
3. **Summary statistics:** Local Mojo scripts report hot-loop `mean` and `best` rather than full bootstrap confidence intervals or tail percentiles.
4. **Code-shape sensitivity:** `experiments/harness.mojo` places many benchmarks in one `main` function, causing means to drift as unrelated code is added; all reported small-message figures come from the isolated `experiments/decode_small.mojo`.

---

## 2. Reference Workloads

Two instances of the eight-field `Message` schema (`f_bool`, `f_int32`, `f_int64`, `f_float64`, `f_string`, `f_bool_2`, `f_int32_2`, `f_string_2`) appear across the experiments:

| Workload | Wire Size | Definition | Used In |
| --- | ---: | --- | --- |
| **Golden `Message`** | `37 B` | Strings `"hi"` (2 B) and `"z"` (1 B); `spec/golden/message.kiln` | `E03`, `E14` |
| **Benchmark `Message`** | `44 B` | Strings `"hello"` (5 B) and `"world"` (5 B); `experiments/decode_small.mojo` & `E15` C baseline | `E01`–`E02`, `E06`, `E08`, `E15`, `E20`–`E24` |
| **100-Message Batch** | `4,404 B` | `struct Batch { items: List[Message] }` (`4 B` count + `100 × 44 B`) | `E01`–`E02`, `E06`, `E10`, `E15`, `E21`–`E24` |
| **10k `Float64` Vector** | `80,192 B` | Single `f64` tensor directory (`64 B` header + `128 B` desc + `80,000 B` payload) | `E07` |
| **2 MiB `Float64` Tensor** | `2,097,344 B` | 262,144 `Float64` values (`2 MiB` payload + `192 B` header/desc) | `E13`, `E25` |

---

## 3. Headline Results (Post-E22–E24)

| Benchmark (`experiments/decode_small.mojo` & `variants.mojo`) | Size | `2026-10-16` Mean | `2026-10-17` Mean | Notes |
| --- | ---: | ---: | ---: | --- |
| Single `Message` encode | `44 B` | `15 ns` | `17 ns` | Reused `Writer`, includes `raises` |
| Single `Message` owned decode (UTF-8 off / trusted) | `44 B` | `28 ns` | `32 ns` | Owned `String` fields |
| 100-`Message` batch encode | `4,404 B` | `339 ns` (`3.4 ns/msg`) | `383 ns` (`3.8 ns/msg`) | Single `List[Message]` struct |
| 100-`Message` batch decode (UTF-8 checked) | `4,404 B` | `1.56 µs` | `1.73 µs` | SWAR ASCII fast-scan (`E24`) |
| 100-`Message` batch decode (UTF-8 skipped) | `4,404 B` | `1.43 µs` | `1.38 µs` | `check_utf8=False` |
| `Writer.copy_bytes()` of 100-message batch | `4,404 B` | `129 ns` | — | Pure buffer materialization |
| 2 MiB `f64` tensor directory encode (`E13`) | `2,097,344 B` | `75 µs` (`write_f64`) | `74 µs` (best `73 µs`) | Python `bytearray` copy same core: best `56 µs`, mean `128 µs` |
| C `-O3` reference encode (`E15`, 100k reps) | `44 B` | `~2.3 ns` | `~2.8 ns` | Mojo `n=1` misses 10% bar; batch `3.4–3.8 ns/msg` is close |

Minor shifts between `2026-10-16` and `2026-10-17` (after landing the v2 tensor directory) did not alter any architectural decision below.

---

## 4. Experiment Matrix (`E00`–`E26`)

### 4.1 Measurement Floor and Wire Layout

| ID | Research Question | Measured Result / Finding | Decision |
| --- | --- | --- | --- |
| **E00** | Is the timer floor above 100 ns? | Empty timed region median ~23–26 ns. | Microbench resolves sub-166 ns codecs; `Writer` is reused. In the GLD runner, `Fixture.empty` avoids copying 5 suite lists across Kiln, CBOR, Avro, EmberJson, and BSON. |
| **E03** | Which length prefix width (`u32` vs narrower)? | Golden message is 37 B with `u32` prefixes (vs. 48 B smallest cited leader). | **Adopt `u32`.** Single uniform width supporting counts `> 65,535`. |
| **E04** | Fixed-width integers vs. LEB128 varints? | Single `UInt64` store and 1-byte LEB128 of `99` both measure mean 17 ns (masked by timer floor). | **Adopt fixed-width LE.** Avoids per-integer decode branches across multi-integer structs and batches. |
| **E09** | Reorder fields (fixed block first) vs. declaration order? | No speedup sufficient to justify diverging from source order. | **Adopt declaration order.** Simplifies schema hashing and source-to-wire correspondence. |
| **E16** | Per-struct `u32` length prefix for schema evolution? | Extra 4 B and store per struct on a path already near the timer floor. | **Reject for default.** Frozen stays untagged; `KLN0` schema hash fails closed. |
| **E17** | Optional-field presence bitmap vs. 1-byte tag? | Requires a second pass or backpatched hole; `Optional` is uncommon in benchmark records. | **Adopt 1-byte tag** (`0x00`/`0x01`). |
| **E18** | String interning table for repeated strings? | Suite message has two distinct strings; adds table overhead. | **Reject.** Dict keys are sorted, not interned. |
| **E20** | Pad small Frozen messages to 64 bytes? | Inflates 44 B message to 64 B without removing any stores. | **Reject on Frozen.** Reserve 64-byte alignment exclusively for `KLNT` tensor payloads. |

### 4.2 Codegen, Buffer Strategy, and Low-Level Stores

| ID | Research Question | Measured Result / Finding | Decision |
| --- | --- | --- | --- |
| **E01** | Does `reflect[T]` match hand-written stores? | Early per-field `reserve` took ~2.9 µs for 100 messages; after `E21`, reflected leaf path is the fast path (`339 ns`). | **Adopt reflection** as the sole struct codec. |
| **E08** | Does `raises` measurably slow the happy path? | Not isolated separately; 15 ns encode includes `raises KilnError` on cold error branch. | **Keep `raises KilnError`** on public API. |
| **E10** | Two-pass pre-sizing with per-field `reserve`? | Moved 100-message batch from ~2.8 µs to ~3.0 µs when paired with checked per-field reserves. | **Caller reuses `Writer`.** Pre-pass re-introduced in `E21` paired with unchecked pointer stores. |
| **E21** | Single size pre-pass + pointer stores for leaf structs? | `n=1`: encode 15 ns, decode 36 ns; `n=100` batch: encode 345 ns, decode 1.80 µs (no UTF-8) / 3.09 µs (UTF-8); `copy_bytes` 129 ns. | **Adopt** for scalar/string structs up to 16 fields; nested structs retain checked writes. |
| **E22** | Unaligned `Pointer.unsafe_store`/`unsafe_load` (`alignment=1`)? | Paired run moved batch encode `443 ns → 339 ns`; batch owned decode (with `E23`–`E24`) `3.32 µs → 1.56 µs`. | **Adopt** when `is_little_endian()` is true; keep byte-shift fallback for big-endian. |
| **E26** | `unsafe_write` into `unsafe_uninit_length` vs. `reserve` + `append` for decoded lists? | 100 structs with 1 short string: `reserve` + `append` best 76 ns vs. `unsafe_write` best 72 ns (`experiments/list_place.mojo`). | **Reject.** Keep simpler `reserve` + `append`. |

### 4.3 Decoding, Views, and Safety Checks

| ID | Research Question | Measured Result / Finding | Decision |
| --- | --- | --- | --- |
| **E02** | Cost of per-field bounds checks on 100-message decode? | Checked reads ~4.5 µs vs. unchecked loads ~0.29 µs. | **Keep `decode` checked.** Expose `Reader.*_fast` solely as an explicit unsafe trusted path. |
| **E05** | Custom SIMD copy for short strings vs. `memcpy`? | Not faster than `memcpy` in isolated probe. | **Keep `memcpy`** in `put_span`. |
| **E06** | Owned `String` decode vs. zero-copy views? | `n=1` owned 36 ns; `n=100` owned 1.80 µs (no UTF-8) / 3.09 µs (UTF-8) vs. view ~0.30 µs. | **Owned `decode` is default;** views via `read_string_slice` / `str_fast`. No separate offset wire layout. |
| **E12** | UTF-8 validation enabled by default? | Measurable cost before `E24`; cut to ~0.13 µs per 100-message batch after `E24`. | **Validate UTF-8 by default** in `decode`; opt-out via `check_utf8=False` for trusted bytes. |
| **E23** | `String(unsafe_uninit_length=)` + `memcpy` vs. span constructor? | 200 escaped 5 B strings: span constructor mean `6,605 ns` vs. uninit fill `1,122 ns` (`experiments/mojo_speed.mojo`). | **Adopt** in `Reader.read_string`. |
| **E24** | 8-byte SWAR ASCII OR-scan before UTF-8 state machine? | Cut 2,000 scans of 200 B ASCII from `83 µs → 12 µs` and 5 B scans `5.5 µs → 2.5 µs` (`experiments/utf8_words.mojo`); batch checked decode `1.56 µs` vs. unchecked `1.43 µs`. | **Adopt.** Any byte `≥ 0x80` falls back to full RFC 3629 state machine. |
| **E25** | `algorithm.vectorize` on Frozen messages? | 5 B strings are below 32 B SIMD chunk width. | **Reject** on Frozen strings; keep single `memcpy` on tensor payloads. |

### 4.4 Numeric Arrays, Tensors, and Unshipped Extensions

| ID | Research Question | Measured Result / Finding | Decision |
| --- | --- | --- | --- |
| **E07** | Bulk `memcpy` for `List[Float64]` / numeric tensors? | 10,000 `f64` (`2026-10-17`): per-element stores `3,674 ns` vs. directory encode `1,612 ns` (~2.3×; pre-directory bulk copy `1,489 ns`). | **Adopt** bulk copy for fixed-width numeric lists and tensor payloads on LE hosts. |
| **E11** | Columnar (SoA) batch profile? | Not shipped; row-wise Frozen batch measured instead. | **Defer.** Profile `4` remains reserved. |
| **E13** | 2 MiB `f64` tensor directory encode throughput? | 262,144 `f64` (`2,097,344 B`): mean `74 µs` (`0.074 ms`), best `73 µs` — well below `0.4 ms` bar and competitive with Python `bytearray` copy (`56 µs` best / `128 µs` mean). | **Ship `KLNT` v2 tensor directory.** |
| **E14** | Built-in compression wrapper? | Golden Frozen message is 37 B; compression latency exceeds size benefit. | **Reject** from wire format; apply externally on large buffers. |
| **E15** | Is Mojo reflection within 10% of C `-O3`? | C `-O3` 44 B encode (`2026-10-17`, 100k reps): `~2.8 ns` vs. Mojo `n=1` `17 ns` (fail) and Mojo `n=100` batch `3.8 ns/msg` (close). | **Ship despite `n=1` gap;** per-record batch throughput approaches the C loop. |
| **E19** | Delta coding for integer lists? | Replaces single bulk `memcpy` (`E07`) with per-element arithmetic. | **Reject.** Preserve raw bit arrays. |

---

## 5. Reproduction

```bash
taskset -c 2 pixi run mojo run -I src experiments/decode_small.mojo
taskset -c 2 pixi run mojo run -I src experiments/mojo_speed.mojo
taskset -c 2 pixi run mojo run -I src experiments/variants.mojo
gcc -O3 -o /tmp/kiln_message experiments/E15-c-ceiling/kiln_message.c
taskset -c 2 /tmp/kiln_message
```
