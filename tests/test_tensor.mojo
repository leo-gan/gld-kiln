from std.collections import List, Span

from kiln import TensorDir, decode, encode, f64_directory
from kiln.wire import Writer


def fail(msg: String) raises:
    raise Error(msg)


def main() raises:
    var data = List[Float64]()
    data.append(1.5)
    data.append(-2.0)
    data.append(0.0)
    var dir = f64_directory(data)
    var w = Writer(256)
    encode(dir, w)
    var back = decode[TensorDir](Span(w.copy_bytes()))
    if len(back.items) != 1 or back.items[0].shape[0] != 3:
        fail("shape")
    var raw = back.items[0].data.copy()
    if len(raw) != 24:
        fail("len " + String(len(raw)))
    if raw[6] != 0xF8 or raw[7] != 0x3F:
        fail("1.5")
    if raw[15] != 0xC0:
        fail("-2")
    var i = 16
    while i < 24:
        if raw[i] != 0:
            fail("zero")
        i += 1
    print("tensor ok")
