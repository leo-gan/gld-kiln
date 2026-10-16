from std.collections import List
from std.time import perf_counter_ns

from kiln.wire import Writer


def leb_u64(mut w: Writer, v: UInt64):
    var n = v
    while True:
        var b = UInt8(n & 0x7F)
        n = n >> 8
        if n == 0:
            w.put_u8(b)
            return
        w.put_u8(b | 0x80)


def main() raises:
    var w = Writer(64)
    var i = 0
    while i < 50:
        w.length = 0
        w.put_u64(UInt64(99))
        i += 1
    var best_f = 1000000000
    var sum_f = 0
    i = 0
    while i < 200:
        w.length = 0
        var a = perf_counter_ns()
        w.put_u64(UInt64(99))
        var b = perf_counter_ns()
        var d = Int(b - a)
        if d < best_f:
            best_f = d
        sum_f += d
        i += 1
    print("fixed_u64", "best", best_f, "mean", sum_f // 200, "len", w.length)
    i = 0
    while i < 50:
        w.length = 0
        leb_u64(w, UInt64(99))
        i += 1
    var best_l = 1000000000
    var sum_l = 0
    i = 0
    while i < 200:
        w.length = 0
        var a = perf_counter_ns()
        leb_u64(w, UInt64(99))
        var b = perf_counter_ns()
        var d = Int(b - a)
        if d < best_l:
            best_l = d
        sum_l += d
        i += 1
    print("leb128_u64", "best", best_l, "mean", sum_l // 200, "len", w.length)

    var xs = List[Float64]()
    var k = 0
    while k < 10000:
        xs.append(Float64(k) * 0.5)
        k += 1
    var wt = Writer(10000 * 8 + 16)
    i = 0
    while i < 5:
        wt.length = 0
        wt.put_u32(UInt32(len(xs)))
        var j = 0
        while j < len(xs):
            wt.put_f64(xs[j])
            j += 1
        i += 1
    var best_loop = 1000000000
    var sum_loop = 0
    i = 0
    while i < 20:
        wt.length = 0
        var a = perf_counter_ns()
        wt.put_u32(UInt32(len(xs)))
        var j = 0
        while j < len(xs):
            wt.put_f64(xs[j])
            j += 1
        var b = perf_counter_ns()
        var d = Int(b - a)
        if d < best_loop:
            best_loop = d
        sum_loop += d
        i += 1
    print("f64_loop_10k", "best", best_loop, "mean", sum_loop // 20, "len", wt.length)
    from kiln.tensor import write_f64
    i = 0
    while i < 5:
        write_f64(xs, wt)
        i += 1
    var best_bulk = 1000000000
    var sum_bulk = 0
    i = 0
    while i < 20:
        var a = perf_counter_ns()
        write_f64(xs, wt)
        var b = perf_counter_ns()
        var d = Int(b - a)
        if d < best_bulk:
            best_bulk = d
        sum_bulk += d
        i += 1
    print("f64_bulk_10k", "best", best_bulk, "mean", sum_bulk // 20, "len", wt.length)
    var big = List[Float64]()
    k = 0
    while k < 262144:
        big.append(0.0)
        k += 1
    var wb = Writer(262144 * 8 + 128)
    i = 0
    while i < 3:
        write_f64(big, wb)
        i += 1
    var best_g = 1000000000
    var sum_g = 0
    i = 0
    while i < 10:
        var a = perf_counter_ns()
        write_f64(big, wb)
        var b = perf_counter_ns()
        var d = Int(b - a)
        if d < best_g:
            best_g = d
        sum_g += d
        i += 1
    print("grid_2mb", "best", best_g, "mean", sum_g // 10, "len", wb.length)
