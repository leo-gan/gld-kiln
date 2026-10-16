from std.collections import Span

from kiln import KilnCodec, KilnError, Writer, decode, encode, type_hash
from kiln.wire import Reader


@fieldwise_init
struct Flag(Copyable, Movable, Defaultable, KilnCodec):
    var on: Bool

    def __init__(out self):
        self.on = False

    def kiln_encode(self, mut w: Writer) raises KilnError:
        if self.on:
            w.put_u8(UInt8(2))
        else:
            w.put_u8(UInt8(3))

    def kiln_size(self) -> Int:
        return 1

    @staticmethod
    def kiln_decode[
        o: ImmOrigin, po: MutOrigin
    ](mut r: Reader[o], ptr: Pointer[Self, po]) raises KilnError:
        var tag = Int(r.u8())
        var v = Flag(tag == 2)
        ptr.unsafe_write(v^)

    @staticmethod
    def kiln_hash(mut h: UInt64):
        h ^= UInt64(7)
        h = h * UInt64(1099511628211)


def fail(msg: String) raises:
    raise Error(msg)


def main() raises:
    var w = Writer(16)
    encode(Flag(True), w)
    var raw = w.copy_bytes()
    if len(raw) != 1 or raw[0] != UInt8(2):
        fail("custom bytes")
    var back = decode[Flag](Span(raw))
    if not back.on:
        fail("custom decode")
    var h1 = type_hash[Flag]()
    var h2 = type_hash[Flag]()
    if h1 != h2:
        fail("hash")
    print("codec ok", h1)
