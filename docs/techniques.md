# Techniques

The field walk is a compile-time loop over `reflect[T].field_count()`, `field_types()`, and `field_ref`. Scalars are little-endian. On a little-endian host each multi-byte scalar is one unaligned store. A list of `Int32`, `Float64`, or another fixed-width number is one `memcpy` on this little-endian host. Strings are a `u32` length and then the UTF-8 bytes.

A struct whose fields are only scalars and strings is measured once. `encode` reserves that many bytes, then writes them through one pointer. On a little-endian target each 2-, 4-, and 8-byte value is one unaligned `Pointer.unsafe_store`. `read_string` copies into `String(unsafe_uninit_length=)` with `memcpy`. An all-ASCII string is accepted by OR-ing its bytes, eight at a time on a little-endian host, and only a byte past 0x7F runs the multi-byte UTF-8 checker. A struct that contains a list, an optional, or another struct still reserves inside those values, so a short nested field cannot write past the bytes it owns. After the first call the buffer is large enough, and later calls do not allocate.

`decode` is the safe entry point. It rejects a length past the end of the buffer before it allocates. `Reader.u32_fast` and `str_fast` skip those checks. The batch measurement uses them, and they are only safe for a buffer whose bounds are already known.

Dict keys are sorted by their UTF-8 bytes before they are written. Iteration order of `Dict` is not part of the wire format.

A custom type can conform to `KilnCodec` and replace the derived field walk. Scalars, `String`, `List`, `Optional`, and `Dict` keep the layout in the spec.
