from std.collections import List, Span

from kiln.tensor import read_f64, write_f64
from kiln.wire import Writer


def fail(msg: String) raises:
    raise Error(msg)


def main() raises:
    var data = List[Float64]()
    data.append(1.5)
    data.append(-2.0)
    data.append(0.0)
    var w = Writer(128)
    write_f64(data, w)
    if w.length != 64 + 24:
        fail("len " + String(w.length))
    var view = Span(w.buf)
    var back = read_f64(view[0:w.length])
    if len(back) != 3 or back[0] != 1.5 or back[1] != -2.0 or back[2] != 0.0:
        fail("values")
    print("tensor ok")
