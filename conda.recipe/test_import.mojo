from kiln import Writer, encode_bytes


@fieldwise_init
struct Pair(Copyable, Movable, Defaultable):
    var n: Int32

    def __init__(out self):
        self.n = 0


def main() raises:
    var raw = encode_bytes(Int32(7))
    if len(raw) != 4:
        raise Error("import encode failed")
    var w = Writer(32)
    _ = w.length
    print("kiln import ok", len(raw))
