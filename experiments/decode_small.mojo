from std.collections import List, Span
from std.time import perf_counter_ns

from kiln import decode, encode, encode_append
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


@fieldwise_init
struct Batch(Copyable, Movable, Defaultable):
    var items: List[Message]

    def __init__(out self):
        self.items = List[Message]()


def main() raises:
    var src = Message(True, Int32(-2), Int64(99), Float64(1.5), "hello", False, Int32(7), "world")
    var w = Writer(8192)
    var sink = 0
    var i = 0
    while i < 30:
        encode(src, w)
        var view = Span(w.buf)
        var back = decode[Message](view[0:w.length], False)
        sink += Int(back.f_int32) + back.f_string.byte_length()
        i += 1
    var best_s = 1000000000
    var best_d = 1000000000
    var sum_s = 0
    var sum_d = 0
    i = 0
    while i < 200:
        var a = perf_counter_ns()
        encode(src, w)
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
        sink += back.f_string.byte_length()
        i += 1
    print("n1", "ser", best_s, sum_s // 200, "de", best_d, sum_d // 200, "len", w.length)

    i = 0
    while i < 5:
        w.length = 0
        var k = 0
        while k < 100:
            encode_append(src, w)
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
            encode_append(src, w)
            k += 1
        var b = perf_counter_ns()
        var d = Int(b - a)
        if d < best_b:
            best_b = d
        sum_b += d
        i += 1
    print("n100_ser", "best", best_b, "mean", sum_b // 40, "len", w.length)

    var view = Span(w.buf)
    var bytes = view[0:w.length]
    var best_o = 1000000000
    var sum_o = 0
    i = 0
    while i < 30:
        var a = perf_counter_ns()
        var pos = 0
        var k = 0
        while k < 100:
            var one = bytes[pos:pos + 44]
            var back = decode[Message](one, False)
            sink += Int(back.f_int32) + back.f_string.byte_length() + back.f_string_2.byte_length()
            pos += 44
            k += 1
        var b = perf_counter_ns()
        var d = Int(b - a)
        if d < best_o:
            best_o = d
        sum_o += d
        i += 1
    print("owned100", "best", best_o, "mean", sum_o // 30, "sink", sink)

    var best_t = 1000000000
    var sum_t = 0
    i = 0
    while i < 30:
        var a = perf_counter_ns()
        var pos = 0
        var k = 0
        while k < 100:
            var one = bytes[pos:pos + 44]
            var back = decode[Message](one, True)
            sink += back.f_string.byte_length()
            pos += 44
            k += 1
        var b = perf_counter_ns()
        var d = Int(b - a)
        if d < best_t:
            best_t = d
        sum_t += d
        i += 1
    print("owned100_utf8", "best", best_t, "mean", sum_t // 30)

    var batch = Batch()
    var k = 0
    while k < 100:
        batch.items.append(src.copy())
        k += 1
    var bw = Writer(8192)
    i = 0
    while i < 5:
        encode(batch, bw)
        i += 1
    var best_bs = 1000000000
    var sum_bs = 0
    i = 0
    while i < 30:
        var a = perf_counter_ns()
        encode(batch, bw)
        var b = perf_counter_ns()
        var d = Int(b - a)
        if d < best_bs:
            best_bs = d
        sum_bs += d
        i += 1
    print("batch_ser", "best", best_bs, "mean", sum_bs // 30, "len", bw.length)

    var bview = Span(bw.buf)
    var bbytes = bview[0:bw.length]
    var best_bd = 1000000000
    var sum_bd = 0
    i = 0
    while i < 20:
        var a = perf_counter_ns()
        var back = decode[Batch](bbytes, True)
        var b = perf_counter_ns()
        sink += len(back.items)
        var d = Int(b - a)
        if d < best_bd:
            best_bd = d
        sum_bd += d
        i += 1
    print("batch_de_utf8", "best", best_bd, "mean", sum_bd // 20, "sink", sink)

    var best_c = 1000000000
    var sum_c = 0
    i = 0
    while i < 30:
        var a = perf_counter_ns()
        var copied = bw.copy_bytes()
        var b = perf_counter_ns()
        sink += len(copied)
        var d = Int(b - a)
        if d < best_c:
            best_c = d
        sum_c += d
        i += 1
    print("copy_bytes", "best", best_c, "mean", sum_c // 30)

    var best_bf = 1000000000
    var sum_bf = 0
    i = 0
    while i < 20:
        var a = perf_counter_ns()
        var back = decode[Batch](bbytes, False)
        var b = perf_counter_ns()
        sink += len(back.items)
        var d = Int(b - a)
        if d < best_bf:
            best_bf = d
        sum_bf += d
        i += 1
    print("batch_de", "best", best_bf, "mean", sum_bf // 20)

    var lw = Writer(8192)
    encode(batch.items, lw)
    var same = bw.length == lw.length
    if same:
        var i2 = 0
        var pb = bw.buf.unsafe_ptr()
        var pl = lw.buf.unsafe_ptr()
        while i2 < bw.length:
            if pb[unsafe_offset=i2] != pl[unsafe_offset=i2]:
                same = False
                break
            i2 += 1
    print("list_matches_batch", same, "len", lw.length, "sink", sink)
