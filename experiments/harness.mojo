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
