from std.collections import Span
from std.time import perf_counter_ns

from kiln import decode, encode, encode_append
from kiln.wire import Reader, Writer


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


def raw_append(m: Message, mut w: Writer):
    """Straight-line stores for this one message shape. A ceiling, not the API."""
    var s0 = m.f_string.as_bytes()
    var s1 = m.f_string_2.as_bytes()
    var n0 = len(s0)
    var n1 = len(s1)
    var i = w.length
    var need = 21 + 4 + n0 + 5 + 4 + n1
    if i + need > len(w.buf):
        w.ensure(need)
        i = w.length
    var p = w.buf.unsafe_ptr()
    if m.f_bool:
        p[unsafe_offset=i] = UInt8(1)
    else:
        p[unsafe_offset=i] = UInt8(0)
    var a = UInt32(m.f_int32.to_bits())
    p[unsafe_offset=i + 1] = UInt8(a)
    p[unsafe_offset=i + 2] = UInt8(a >> 8)
    p[unsafe_offset=i + 3] = UInt8(a >> 16)
    p[unsafe_offset=i + 4] = UInt8(a >> 24)
    var b = UInt64(m.f_int64.to_bits())
    var k = i + 5
    p[unsafe_offset=k] = UInt8(b)
    p[unsafe_offset=k + 1] = UInt8(b >> 8)
    p[unsafe_offset=k + 2] = UInt8(b >> 16)
    p[unsafe_offset=k + 3] = UInt8(b >> 24)
    p[unsafe_offset=k + 4] = UInt8(b >> 32)
    p[unsafe_offset=k + 5] = UInt8(b >> 40)
    p[unsafe_offset=k + 6] = UInt8(b >> 48)
    p[unsafe_offset=k + 7] = UInt8(b >> 56)
    var c = UInt64(m.f_float64.to_bits())
    k = i + 13
    p[unsafe_offset=k] = UInt8(c)
    p[unsafe_offset=k + 1] = UInt8(c >> 8)
    p[unsafe_offset=k + 2] = UInt8(c >> 16)
    p[unsafe_offset=k + 3] = UInt8(c >> 24)
    p[unsafe_offset=k + 4] = UInt8(c >> 32)
    p[unsafe_offset=k + 5] = UInt8(c >> 40)
    p[unsafe_offset=k + 6] = UInt8(c >> 48)
    p[unsafe_offset=k + 7] = UInt8(c >> 56)
    k = i + 21
    var n0u = UInt32(n0)
    p[unsafe_offset=k] = UInt8(n0u)
    p[unsafe_offset=k + 1] = UInt8(n0u >> 8)
    p[unsafe_offset=k + 2] = UInt8(n0u >> 16)
    p[unsafe_offset=k + 3] = UInt8(n0u >> 24)
    var s = 0
    while s < n0:
        p[unsafe_offset=k + 4 + s] = s0[s]
        s += 1
    k = k + 4 + n0
    if m.f_bool_2:
        p[unsafe_offset=k] = UInt8(1)
    else:
        p[unsafe_offset=k] = UInt8(0)
    var d = UInt32(m.f_int32_2.to_bits())
    p[unsafe_offset=k + 1] = UInt8(d)
    p[unsafe_offset=k + 2] = UInt8(d >> 8)
    p[unsafe_offset=k + 3] = UInt8(d >> 16)
    p[unsafe_offset=k + 4] = UInt8(d >> 24)
    k = k + 5
    var n1u = UInt32(n1)
    p[unsafe_offset=k] = UInt8(n1u)
    p[unsafe_offset=k + 1] = UInt8(n1u >> 8)
    p[unsafe_offset=k + 2] = UInt8(n1u >> 16)
    p[unsafe_offset=k + 3] = UInt8(n1u >> 24)
    s = 0
    while s < n1:
        p[unsafe_offset=k + 4 + s] = s1[s]
        s += 1
    w.length = k + 4 + n1


def main() raises:
    var m = sample()
    var w = Writer(256)
    var i = 0
    var sink = 0
    while i < 30:
        encode(m, w)
        var view = Span(w.buf)
        var back = decode[Message](view[0:w.length], False)
        sink += Int(back.f_int32)
        i += 1
    var best_s = 1000000000
    var best_d = 1000000000
    var sum_s = 0
    var sum_d = 0
    i = 0
    while i < 200:
        var a = perf_counter_ns()
        encode(m, w)
        var b = perf_counter_ns()
        var view = Span(w.buf)
        var back = decode[Message](view[0:w.length], False)
        var c = perf_counter_ns()
        var ds = Int(b - a)
        var dd = Int(c - b)
        if ds < best_s:
            best_s = ds
        if dd < best_d:
            best_d = dd
        sum_s += ds
        sum_d += dd
        sink += Int(back.f_string.as_bytes()[0])
        i += 1
    print("n1_ser", "best", best_s, "mean", sum_s // 200)
    print("n1_de", "best", best_d, "mean", sum_d // 200, "len", w.length, "sink", sink)

    i = 0
    while i < 5:
        w.length = 0
        var k = 0
        while k < 100:
            encode_append(m, w)
            k += 1
        i += 1
    var best_b = 1000000000
    var sum_b = 0
    i = 0
    while i < 40:
        w.length = 0
        var a = perf_counter_ns()
        var k = 0
        while k < 100:
            encode_append(m, w)
            k += 1
        var b = perf_counter_ns()
        var d = Int(b - a)
        if d < best_b:
            best_b = d
        sum_b += d
        i += 1
    print("n100_ser", "best", best_b, "mean", sum_b // 40, "len", w.length)

    var batch = Span(w.buf)
    var sp = batch[0:w.length]
    var r = Reader(sp, False)
    var sink2 = 0
    i = 0
    while i < 5:
        r.pos = 0
        var k = 0
        while k < 100:
            sink2 += Int(r.u8_fast())
            sink2 += Int(r.u32_fast())
            _ = r.u64_fast()
            _ = r.u64_fast()
            var s0 = r.str_fast()
            sink2 += Int(r.u8_fast())
            sink2 += Int(r.u32_fast())
            var s1 = r.str_fast()
            sink2 += s0.byte_length() + s1.byte_length()
            k += 1
        i += 1
    if r.pos != w.length:
        raise Error("view did not consume the batch")
    var best_v = 1000000000
    var sum_v = 0
    i = 0
    while i < 40:
        r.pos = 0
        var a = perf_counter_ns()
        var k = 0
        while k < 100:
            sink2 += Int(r.u8_fast())
            sink2 += Int(r.u32_fast())
            _ = r.u64_fast()
            _ = r.u64_fast()
            var s0 = r.str_fast()
            sink2 += Int(r.u8_fast())
            sink2 += Int(r.u32_fast())
            var s1 = r.str_fast()
            sink2 += s0.byte_length() + s1.byte_length()
            k += 1
        var b = perf_counter_ns()
        var d = Int(b - a)
        if d < best_v:
            best_v = d
        sum_v += d
        i += 1
    print("n100_view", "best", best_v, "mean", sum_v // 40, "pos", r.pos, "sink", sink2)

    i = 0
    var best_raw = 1000000000
    var sum_raw = 0
    while i < 30:
        w.length = 0
        raw_append(m, w)
        i += 1
    i = 0
    while i < 200:
        w.length = 0
        var a = perf_counter_ns()
        raw_append(m, w)
        var b = perf_counter_ns()
        var d = Int(b - a)
        if d < best_raw:
            best_raw = d
        sum_raw += d
        sink += w.length
        i += 1
    print("raw1", "best", best_raw, "mean", sum_raw // 200, "len", w.length)
    var best_raw100 = 1000000000
    var sum_raw100 = 0
    i = 0
    while i < 40:
        w.length = 0
        var a = perf_counter_ns()
        var k = 0
        while k < 100:
            raw_append(m, w)
            k += 1
        var b = perf_counter_ns()
        var d = Int(b - a)
        if d < best_raw100:
            best_raw100 = d
        sum_raw100 += d
        i += 1
    print("raw100", "best", best_raw100, "mean", sum_raw100 // 40, "len", w.length, "sink", sink)

    var owned_best = 1000000000
    var owned_sum = 0
    i = 0
    while i < 20:
        w.length = 0
        var k = 0
        while k < 100:
            encode_append(m, w)
            k += 1
        var view = Span(w.buf)
        var sp = view[0:w.length]
        var a = perf_counter_ns()
        var pos = 0
        k = 0
        while k < 100:
            var one = sp[pos:pos + 44]
            var back = decode[Message](one, False)
            sink += Int(back.f_int32)
            pos += 44
            k += 1
        var b = perf_counter_ns()
        var d = Int(b - a)
        if d < owned_best:
            owned_best = d
        owned_sum += d
        i += 1
    print("owned100", "best", owned_best, "mean", owned_sum // 20, "sink", sink)

    var raw_de_best = 1000000000
    var raw_de_sum = 0
    i = 0
    while i < 20:
        w.length = 0
        var k = 0
        while k < 100:
            raw_append(m, w)
            k += 1
        var view = Span(w.buf)
        var sp = view[0:w.length]
        var a = perf_counter_ns()
        var pos = 0
        k = 0
        while k < 100:
            var base = pos
            var p = sp.unsafe_ptr()
            var msg = Message()
            msg.f_bool = p[unsafe_offset=base] == UInt8(1)
            var i32 = UInt32(p[unsafe_offset=base + 1])
            i32 = i32 | (UInt32(p[unsafe_offset=base + 2]) << 8)
            i32 = i32 | (UInt32(p[unsafe_offset=base + 3]) << 16)
            i32 = i32 | (UInt32(p[unsafe_offset=base + 4]) << 24)
            msg.f_int32 = Int32(from_bits=i32)
            var n0 = Int(p[unsafe_offset=base + 21])
            var sl = sp[base + 25:base + 25 + n0]
            msg.f_string = String(unsafe_from_utf8=sl)
            var n1 = Int(p[unsafe_offset=base + 35])
            var sl2 = sp[base + 39:base + 39 + n1]
            msg.f_string_2 = String(unsafe_from_utf8=sl2)
            sink += Int(msg.f_int32) + msg.f_string.byte_length() + msg.f_string_2.byte_length()
            pos += 44
            k += 1
        var b = perf_counter_ns()
        var d = Int(b - a)
        if d < raw_de_best:
            raw_de_best = d
        raw_de_sum += d
        i += 1
    print("raw_owned100", "best", raw_de_best, "mean", raw_de_sum // 20, "sink", sink)
