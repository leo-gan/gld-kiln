# Harness output

Command: `taskset -c 2 pixi run mojo run -I src experiments/harness.mojo`

Machine: Intel i7-12800H, powersave, core 2, Mojo 1.1.0, 2026-10-16.

```
n1_ser best 37 mean 38
n1_de best 89 mean 90 len 44 sink 20740
n100_ser best 2903 mean 2952 len 4400
n100_view best 293 mean 295 pos 4400 sink 19327352904000
```

`pos 4400` is 100 messages of 44 bytes. The view reader consumed the whole buffer.

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

The C decode total is a few microseconds for 100,000 calls, so the mean rounds to 0 ns. The C encode mean is about 2.3 ns. Mojo reflection encode is about 38 ns.
