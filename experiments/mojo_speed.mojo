"""Ideas from the Mojo 1.1 manual and stdlib docs, measured on one message shape.

Docs used:
- std.sys.info.is_little_endian and UnsafePointer store/load
- memory.bitcast, described as a register-level reinterpret
- String(unsafe_uninit_length) plus unsafe_ptr_mut, the SSO write path
- algorithm.vectorize, which the algorithm package says is for large arrays

The message is the same 44-byte probe as decode_small.mojo.
"""

from std.collections import List, Span
from std.memory import bitcast, unsafe_memcpy
from std.sys import is_little_endian
from std.time import perf_counter_ns

from kiln import decode, encode
from kiln.utf8 import utf8_ok
from kiln.wire import Writer


@fieldwise_init
struct Message(Copyable, Movable, Defaultable):
    var f_bool: Bool
    var f_int32: Int32
    var f_int64: Int64
    var f_float64: Float64
    var f_string: String
    var f_bool_2: Bool
    var f_int32_2: Int32
    var f_string_2: String

    def __init__(out self):
        self.f_bool = False
        self.f_int32 = 0
        self.f_int64 = 0
        self.f_float64 = 0.0
        self.f_string = ""
        self.f_bool_2 = False
        self.f_int32_2 = 0
        self.f_string_2 = ""


def sample() -> Message:
    return Message(True, Int32(-2), Int64(99), Float64(1.5), "hello", False, Int32(7), "world")


def store_bytes[o: MutOrigin](p: Pointer[UInt8, o], i: Int, v: UInt64):
    p[unsafe_offset=i] = UInt8(v)
    p[unsafe_offset=i + 1] = UInt8(v >> 8)
    p[unsafe_offset=i + 2] = UInt8(v >> 16)
    p[unsafe_offset=i + 3] = UInt8(v >> 24)
    p[unsafe_offset=i + 4] = UInt8(v >> 32)
    p[unsafe_offset=i + 5] = UInt8(v >> 40)
    p[unsafe_offset=i + 6] = UInt8(v >> 48)
    p[unsafe_offset=i + 7] = UInt8(v >> 56)


def store_word[o: MutOrigin](p: Pointer[UInt8, o], i: Int, v: UInt64):
    """One unaligned SIMD store. The manual documents Pointer.store alignment=1."""
    var q = p.unsafe_offset(i).unsafe_bitcast[Scalar[DType.uint64]]()
    q.unsafe_store[alignment=1](0, v)


def ascii_ok[o: ImmOrigin](sp: Span[UInt8, o]) -> Bool:
    var n = len(sp)
    var p = sp.unsafe_ptr()
    var bits = UInt8(0)
    var i = 0
    while i < n:
        bits = bits | p[unsafe_offset=i]
        i += 1
    if bits < UInt8(0x80):
        return True
    return utf8_ok(sp)


def main() raises:
    print("little_endian", is_little_endian())
    var buf = List[UInt8](unsafe_uninit_length=64)
    var p = buf.unsafe_ptr()
    var word = UInt64(0x0807060504030201)
    store_word(p, 0, word)
    var backp = p.unsafe_bitcast[Scalar[DType.uint64]]()
    var got = backp.unsafe_load[alignment=1](0)
    print("word_roundtrip", got == word, "b0", Int(p[unsafe_offset=0]))

    var m = sample()
    var w = Writer(8192)
    var k = 0
    while k < 5:
        w.length = 0
        var j = 0
        while j < 100:
            encode(m, w)
            j += 1
        k += 1
    var best = 1000000000
    var sum = 0
    k = 0
    while k < 40:
        w.length = 0
        var t0 = perf_counter_ns()
        var j = 0
        while j < 100:
            encode(m, w)
            j += 1
        var t1 = perf_counter_ns()
        var d = Int(t1 - t0)
        if d < best:
            best = d
        sum += d
        k += 1
    print("encode100", "best", best, "mean", sum // 40, "len", w.length)

    var scratch = List[UInt8](unsafe_uninit_length=16)
    var sptr = scratch.unsafe_ptr()
    best = 1000000000
    sum = 0
    k = 0
    while k < 40:
        var t0 = perf_counter_ns()
        var j = 0
        while j < 1000:
            store_bytes(sptr, 0, word)
            store_bytes(sptr, 8, word)
            j += 1
        var t1 = perf_counter_ns()
        var d = Int(t1 - t0)
        if d < best:
            best = d
        sum += d
        k += 1
    print("byte_stores_2k", "best", best, "mean", sum // 40, "sink", Int(sptr[unsafe_offset=0]))

    best = 1000000000
    sum = 0
    k = 0
    while k < 40:
        var t0 = perf_counter_ns()
        var j = 0
        while j < 1000:
            store_word(sptr, 0, word)
            store_word(sptr, 8, word)
            j += 1
        var t1 = perf_counter_ns()
        var d = Int(t1 - t0)
        if d < best:
            best = d
        sum += d
        k += 1
    print("word_stores_2k", "best", best, "mean", sum // 40, "sink", Int(sptr[unsafe_offset=0]))

    var hello = String("hello")
    var hb = hello.as_bytes()
    var long = String("hello world hello world hello world hello world hello!!!!")
    var lb = long.as_bytes()
    var sink = 0
    best = 1000000000
    sum = 0
    k = 0
    while k < 20:
        var t0 = perf_counter_ns()
        var j = 0
        while j < 2000:
            if utf8_ok(hb):
                sink += 1
            if utf8_ok(lb):
                sink += 1
            j += 1
        var t1 = perf_counter_ns()
        var d = Int(t1 - t0)
        if d < best:
            best = d
        sum += d
        k += 1
    print("utf8_scan", "best", best, "mean", sum // 20)

    best = 1000000000
    sum = 0
    k = 0
    while k < 20:
        var t0 = perf_counter_ns()
        var j = 0
        while j < 2000:
            if ascii_ok(hb):
                sink += 1
            if ascii_ok(lb):
                sink += 1
            j += 1
        var t1 = perf_counter_ns()
        var d = Int(t1 - t0)
        if d < best:
            best = d
        sum += d
        k += 1
    print("ascii_then_utf8", "best", best, "mean", sum // 20, "sink", sink)

    var raw = List[UInt8](unsafe_uninit_length=8)
    var nlen = 5
    var ri = 0
    while ri < 5:
        raw[ri] = hb[ri]
        ri += 1
    var rsp = Span(raw)
    var rp = rsp.unsafe_ptr()
    var kept = List[String]()
    kept.reserve(200)
    best = 1000000000
    sum = 0
    k = 0
    while k < 20:
        kept.clear()
        var t0 = perf_counter_ns()
        var j = 0
        while j < 100:
            var a = String(unsafe_from_utf8=rsp[0:nlen])
            kept.append(a^)
            var b = String(unsafe_from_utf8=rsp[0:nlen])
            kept.append(b^)
            j += 1
        var t1 = perf_counter_ns()
        var d = Int(t1 - t0)
        if d < best:
            best = d
        sum += d
        k += 1
    print("string_from_span", "best", best, "mean", sum // 20, "n", len(kept))

    best = 1000000000
    sum = 0
    k = 0
    while k < 20:
        kept.clear()
        var t0 = perf_counter_ns()
        var j = 0
        while j < 100:
            var a = String(unsafe_uninit_length=nlen)
            unsafe_memcpy(dest=a.unsafe_ptr_mut(), src=rp, count=nlen)
            kept.append(a^)
            var b = String(unsafe_uninit_length=nlen)
            unsafe_memcpy(dest=b.unsafe_ptr_mut(), src=rp, count=nlen)
            kept.append(b^)
            j += 1
        var t1 = perf_counter_ns()
        var d = Int(t1 - t0)
        if d < best:
            best = d
        sum += d
        k += 1
    print("string_uninit", "best", best, "mean", sum // 20, "s0", kept[0], "sink", sink)

    _ = bitcast[DType.uint8, 8](word)
    var view = Span(w.buf)
    var back = decode[Message](view[0:44], False)
    print("decode_check", Int(back.f_int32), back.f_string)
