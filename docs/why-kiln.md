# Why Kiln

A Mojo program that sends a struct to another process, or stores it in a file, has to pick an encoding. Many encodings write a name or a numeric tag in front of every value. That name helps a reader that does not know which field comes next. When both programs were compiled from the same struct, the order is already fixed, and the name on the wire repeats it.

Kiln was written for the case where the struct is the schema. `reflect` walks the fields when the program compiles and the encoder stores them in that order: little-endian integers and floats, then a `u32` length and the bytes of each string. The same idea is what the fastest small-message codecs in the GLD comparison do. Zig `comptime-bin`, C++ `dagr-frozen`, Rust `speedy`, and a hand-written C encoder all write fixed-width little-endian numbers and a length before each string. Kiln uses that layout and implements it in Mojo, so the program does not call a C, C++, or Rust library to move its own structs.

The cost shows up in two places. One small record is a handful of stores plus the copy of its strings. A batch is that record repeated, so a branch or an allocation per field is paid once per record. Kiln keeps a `Writer` the caller can reuse across calls. For a struct made only of scalars and strings, it measures the byte count once and then stores through one pointer. A large array of `Float64` is a third case. The tensor block is a 64-byte header and a raw copy, because walking each number as its own field would only add loop overhead.

`decode` still rejects a length that would read past the buffer, and it checks UTF-8 unless the caller has already marked the bytes as trusted. The speed comes from the layout and from the compile-time field walk. A hostile count still fails before Kiln allocates.

This version is for programs that share one struct definition. An optional frame stores a hash of the type and rejects the buffer when the struct no longer matches. Updating old files field by field would add a length and a skip to every value, which is the overhead the frozen layout is there to remove. When a JSON Schema file is the source of the types, `gld-kilngen-mojo` reads a documented subset and writes the Mojo structs. The bytes stay positional.

A separate wire profile is shipped only when an experiment meets the bar written down for it. Frozen is the default. The tensor block is the other shipped layout.
