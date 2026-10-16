# Why Kiln

Tagged formats spend bytes and branches on a field key before the value. The fastest rows in the GLD suite skip that work. Zig `comptime-bin`, C++ `dagr-frozen`, Rust `speedy`, and a hand-written C encoder all write fixed-width little-endian numbers and a length before each string. Kiln uses that layout, and it builds the field walk with Mojo `reflect` when the program compiles.

A separate wire profile is shipped only when an experiment meets the bar written down for it. Frozen is the default. The tensor block is the other shipped layout, because a 2 MB array of `Float64` is a copy, not a field walk.

Kiln does not aim to be a general schema-evolution format. An optional frame carries a hash of the type so a file can be rejected when the struct changed. Old and new structs are not reconciled field by field in this version.
