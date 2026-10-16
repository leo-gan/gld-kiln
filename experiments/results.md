# Harness output

Command: `taskset -c 2 pixi run mojo run -I src experiments/harness.mojo`

Machine: Intel i7-12800H, powersave, core 2, Mojo 1.1.0, 2026-10-16.

The long harness shares one large `main`, and its means move when that file grows. The numbers below are from `experiments/decode_small.mojo` after the leaf-struct cursor landed. Same machine, same command shape.

```
n1 ser 14 15 de 35 36 len 44
n100_ser best 463 mean 483 len 4400
owned100 best 2528 mean 2552
owned100_utf8 best 3505 mean 3632
batch_ser best 337 mean 345 len 4404
batch_de_utf8 best 2771 mean 3092
copy_bytes best 48 mean 129
batch_de best 1747 mean 1797
list_matches_batch True len 4404
```

`n1` prints best then mean for encode, then best then mean for decode. The batch is one struct with a list of 100 messages (4404 bytes: a 4-byte count plus 100 times 44). `list_matches_batch True` means those bytes match `encode` of the list alone. Decode of that batch with UTF-8 checking is the `batch_de_utf8` row. `batch_de` skips the UTF-8 check.

`experiments/variants.mojo` on the same core:

```
fixed_u64 best 16 mean 17 len 8
leb128_u64 best 15 mean 17 len 1
f64_loop_10k best 3741 mean 3981 len 80004
f64_bulk_10k best 1458 mean 1489 len 80064
grid_2mb best 71434 mean 74671 len 2097216
```

`gcc -O3` on `experiments/E15-c-ceiling/kiln_message.c`, 100,000 repetitions:

```
c_encode_mean 2 total_ns 233226 len 44
c_decode_mean 0 total_ns 7317
```

The C decode total is a few microseconds for 100,000 calls, so the mean rounds to 0 ns. The C encode mean is about 2.3 ns. Mojo reflection encode of one message is mean 15 ns in `decode_small.mojo` after E22. That is still more than 10% above the C loop, so E15 stays a failure. The batch encode is mean 339 ns, about 3.4 ns per message.

A later paired run of the same file, after unaligned loads and stores, the uninitialized string fill, and the ASCII UTF-8 scan:

```
n1 ser 14 15 de 27 28 len 44
n100_ser best 466 mean 478 len 4400
owned100 best 1720 mean 1728
owned100_utf8 best 1764 mean 1776
batch_ser best 337 mean 339 len 4404
batch_de_utf8 best 1394 mean 1558
batch_de best 1411 mean 1426
list_matches_batch True len 4404
```

`experiments/mojo_speed.mojo` on the same core, before those library changes, printed `string_from_span` mean 7168 ns and `string_uninit` mean 1126 ns for 200 escaped 5-byte strings. `word_roundtrip True` checked that `Pointer.unsafe_store` of a `UInt64` came back little-endian. The byte-store and word-store micro loops both hit a 14 ns best and are not used as the adopt/reject signal. The batch encode in `decode_small.mojo` is.
