"""List.append after reserve versus Pointer.unsafe_write into uninitialized slots.

The pointer manual says unsafe_write initializes memory that is not yet
a live value. List(unsafe_uninit_length=) is that memory. Measured on
100 messages that each own one short string.
"""

from std.time import perf_counter_ns


@fieldwise_init
struct Message(Copyable, Movable, Defaultable):
    var n: Int32
    var s: String

    def __init__(out self):
        self.n = 0
        self.s = ""


def main():
    var i = 0
    var sink = 0
    var best_a = 1000000000
    var best_u = 1000000000
    while i < 30:
        var t0 = perf_counter_ns()
        var out = List[Message]()
        out.reserve(100)
        var k = 0
        while k < 100:
            var m = Message(Int32(k), String("hello"))
            out.append(m^)
            k += 1
        var t1 = perf_counter_ns()
        sink += len(out)
        var d = Int(t1 - t0)
        if d < best_a:
            best_a = d
        i += 1
    print("append", best_a, "sink", sink)

    i = 0
    while i < 30:
        var t0 = perf_counter_ns()
        var out = List[Message](unsafe_uninit_length=100)
        var p = out.unsafe_ptr()
        var k = 0
        while k < 100:
            var m = Message(Int32(k), String("hello"))
            p.unsafe_offset(k).unsafe_write(m^)
            k += 1
        var t1 = perf_counter_ns()
        sink += len(out) + Int(out[0].n) + out[0].s.byte_length()
        var d = Int(t1 - t0)
        if d < best_u:
            best_u = d
        i += 1
    print("uninit", best_u, "sink", sink)
