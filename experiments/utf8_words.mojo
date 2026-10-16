from std.collections import List, Span
from std.time import perf_counter_ns

from kiln.utf8 import utf8_ok


def fill(mut raw: List[UInt8], n: Int, mark: UInt8):
    var i = 0
    while i < n:
        raw[i] = UInt8(0x61)
        i += 1
    raw[n - 1] = mark


def bench(sp: Span[UInt8, _], label: String) -> Int:
    var sink = 0
    var best = 1000000000
    var sum = 0
    var k = 0
    while k < 30:
        var t0 = perf_counter_ns()
        var j = 0
        while j < 2000:
            if utf8_ok(sp):
                sink += 1
            j += 1
        var t1 = perf_counter_ns()
        var d = Int(t1 - t0)
        if d < best:
            best = d
        sum += d
        k += 1
    print(label, "best", best, "mean", sum // 30, "sink", sink, "n", len(sp))
    return sink


def main():
    var short = List[UInt8](unsafe_uninit_length=8)
    fill(short, 5, UInt8(0x62))
    var long = List[UInt8](unsafe_uninit_length=256)
    fill(long, 200, UInt8(0x63))
    var bad = List[UInt8](unsafe_uninit_length=16)
    fill(bad, 8, UInt8(0xFF))
    _ = bench(Span(short)[0:5], String("ascii5"))
    _ = bench(Span(long)[0:200], String("ascii200"))
    var sink = 0
    if not utf8_ok(Span(bad)[0:8]):
        sink += 1
    print("rejected", sink)
