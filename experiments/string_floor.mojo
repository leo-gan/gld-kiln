# Probe for where owned-decode time goes.
# Rows whose lengths are compile-time constants can be deleted by the optimizer.
# escape_strings, reflect_owned, and manual_owned keep the strings alive.
from std.collections import List, Span
from std.time import perf_counter_ns

from kiln import decode, encode_append
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


def main() raises:
    var hello = String("hello")
    var world = String("world")
    var h = hello.as_bytes()
    var wds = world.as_bytes()
    var raw = List[UInt8](unsafe_uninit_length=64)
    var n = 0
    while n < 5:
        raw[n] = h[n]
        raw[5 + n] = wds[n]
        n += 1
    var sp = Span(raw)
    var p = sp.unsafe_ptr()
    var sink = 0
    var round = 0
    while round < 5:
        var k = 0
        while k < 100:
            var a = String(unsafe_from_utf8=h)
            var b = String(unsafe_from_utf8=wds)
            sink += a.byte_length() + b.byte_length()
            k += 1
        round += 1
    var best = 1000000000
    var sum = 0
    round = 0
    while round < 30:
        var t0 = perf_counter_ns()
        var k = 0
        while k < 100:
            var a = String(unsafe_from_utf8=h)
            var b = String(unsafe_from_utf8=wds)
            sink += a.byte_length() + b.byte_length()
            k += 1
        var t1 = perf_counter_ns()
        var d = Int(t1 - t0)
        if d < best:
            best = d
        sum += d
        round += 1
    print("from_bytes", "best", best, "mean", sum // 30)

    best = 1000000000
    sum = 0
    round = 0
    while round < 10:
        var k = 0
        while k < 100:
            var a = String(unsafe_from_utf8=sp[0:5])
            var b = String(unsafe_from_utf8=sp[5:10])
            sink += a.byte_length() + b.byte_length()
            k += 1
        round += 1
    round = 0
    while round < 30:
        var t0 = perf_counter_ns()
        var k = 0
        while k < 100:
            var a = String(unsafe_from_utf8=sp[0:5])
            var b = String(unsafe_from_utf8=sp[5:10])
            sink += a.byte_length() + b.byte_length()
            k += 1
        var t1 = perf_counter_ns()
        var d = Int(t1 - t0)
        if d < best:
            best = d
        sum += d
        round += 1
    print("from_slice", "best", best, "mean", sum // 30)

    best = 1000000000
    sum = 0
    round = 0
    while round < 10:
        var k = 0
        while k < 100:
            var n0 = Int(p[unsafe_offset=4])
            if n0 > 5:
                n0 = 5
            var a = String(unsafe_from_utf8=sp[0:n0])
            var b = String(unsafe_from_utf8=sp[5:10])
            sink += a.byte_length() + b.byte_length()
            k += 1
        round += 1
    round = 0
    while round < 30:
        var t0 = perf_counter_ns()
        var k = 0
        while k < 100:
            var n0 = Int(p[unsafe_offset=4])
            if n0 > 5:
                n0 = 5
            var a = String(unsafe_from_utf8=sp[0:n0])
            var b = String(unsafe_from_utf8=sp[5:10])
            sink += a.byte_length() + b.byte_length()
            k += 1
        var t1 = perf_counter_ns()
        var d = Int(t1 - t0)
        if d < best:
            best = d
        sum += d
        round += 1
    print("from_runtime", "best", best, "mean", sum // 30)

    best = 1000000000
    sum = 0
    round = 0
    while round < 30:
        var t0 = perf_counter_ns()
        var k = 0
        while k < 100:
            var m = Message()
            sink += Int(m.f_int32)
            k += 1
        var t1 = perf_counter_ns()
        var d = Int(t1 - t0)
        if d < best:
            best = d
        sum += d
        round += 1
    print("just_ctor", "best", best, "mean", sum // 30)

    best = 1000000000
    sum = 0
    round = 0
    while round < 30:
        var t0 = perf_counter_ns()
        var k = 0
        while k < 100:
            var m = Message()
            m.f_string = String(unsafe_from_utf8=sp[0:5])
            m.f_string_2 = String(unsafe_from_utf8=sp[5:10])
            sink += m.f_string.byte_length() + m.f_string_2.byte_length()
            k += 1
        var t1 = perf_counter_ns()
        var d = Int(t1 - t0)
        if d < best:
            best = d
        sum += d
        round += 1
    print("ctor_and_strings", "best", best, "mean", sum // 30, "sink", sink)

    var src = Message(True, Int32(-2), Int64(99), Float64(1.5), "hello", False, Int32(7), "world")
    var writer = Writer(8192)
    var k = 0
    while k < 100:
        encode_append(src, writer)
        k += 1
    var view = Span(writer.buf)
    var bytes = view[0:writer.length]
    var bp = bytes.unsafe_ptr()

    best = 1000000000
    sum = 0
    round = 0
    while round < 20:
        var t0 = perf_counter_ns()
        var pos = 0
        k = 0
        while k < 100:
            var one = bytes[pos:pos + 44]
            var back = decode[Message](one, False)
            sink += Int(back.f_int32) + back.f_string.byte_length()
            pos += 44
            k += 1
        var t1 = perf_counter_ns()
        var d = Int(t1 - t0)
        if d < best:
            best = d
        sum += d
        round += 1
    print("reflect_owned", "best", best, "mean", sum // 20)

    best = 1000000000
    sum = 0
    round = 0
    while round < 20:
        var t0 = perf_counter_ns()
        var pos = 0
        k = 0
        while k < 100:
            var base = pos
            var msg = Message()
            msg.f_bool = bp[unsafe_offset=base] == UInt8(1)
            var i32 = UInt32(bp[unsafe_offset=base + 1])
            i32 = i32 | (UInt32(bp[unsafe_offset=base + 2]) << 8)
            i32 = i32 | (UInt32(bp[unsafe_offset=base + 3]) << 16)
            i32 = i32 | (UInt32(bp[unsafe_offset=base + 4]) << 24)
            msg.f_int32 = Int32(from_bits=i32)
            var n0 = Int(bp[unsafe_offset=base + 21])
            msg.f_string = String(unsafe_from_utf8=bytes[base + 25:base + 25 + n0])
            var n1_at = base + 30 + n0
            var n1 = Int(bp[unsafe_offset=n1_at])
            var str2 = n1_at + 4
            msg.f_string_2 = String(unsafe_from_utf8=bytes[str2:str2 + n1])
            sink += Int(msg.f_int32) + msg.f_string.byte_length() + msg.f_string_2.byte_length()
            pos = str2 + n1
            k += 1
        var t1 = perf_counter_ns()
        var d = Int(t1 - t0)
        if d < best:
            best = d
        sum += d
        round += 1
    print("manual_owned", "best", best, "mean", sum // 20, "sink", sink)

    raw[60] = UInt8(5)
    var kept = List[String]()
    kept.reserve(200)
    var nlen = Int(raw[60])
    best = 1000000000
    sum = 0
    round = 0
    while round < 20:
        kept.clear()
        var t0 = perf_counter_ns()
        var k2 = 0
        while k2 < 100:
            var a = String(unsafe_from_utf8=sp[0:nlen])
            var b = String(unsafe_from_utf8=sp[5:5 + nlen])
            kept.append(a^)
            kept.append(b^)
            k2 += 1
        var t1 = perf_counter_ns()
        var d = Int(t1 - t0)
        if d < best:
            best = d
        sum += d
        round += 1
    print("escape_strings", "best", best, "mean", sum // 20, "n", len(kept), "sink", sink)
