from std.collections import List, Span

from kiln import decode_bytes, decode_framed, encode_bytes, encode_framed
from kiln.wire import Writer


@fieldwise_init
struct Point(Copyable, Movable, Defaultable):
    var x: Int32
    var y: Int32

    def __init__(out self):
        self.x = 0
        self.y = 0


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


def fail(msg: String) raises:
    raise Error(msg)


def read_file(path: String) raises -> List[UInt8]:
    var f = open(path, "r")
    var data = f.read_bytes()
    f.close()
    return data^


def same(got: List[UInt8], want: List[UInt8], label: String) raises:
    if len(got) != len(want):
        fail(label + " len " + String(len(got)) + " != " + String(len(want)))
    var i = 0
    while i < len(got):
        if got[i] != want[i]:
            fail(label + " byte " + String(i))
        i += 1


def main() raises:
    var message = Message(True, Int32(-2), Int64(99), Float64(1.5), "hi", False, Int32(7), "z")
    var got = encode_bytes(message)
    var want = read_file("spec/golden/message.kiln")
    same(got, want, "message")
    var back = decode_bytes[Message](want)
    if back.f_string != "hi" or back.f_int32 != Int32(-2) or back.f_string_2 != "z":
        fail("message decode")
    var w = Writer()
    encode_framed(message, w)
    var framed = w.copy_bytes()
    var want_frame = read_file("spec/golden/message.frame.kiln")
    same(framed, want_frame, "frame")
    var back_f = decode_framed[Message](Span(want_frame))
    if back_f.f_int64 != Int64(99) or not back_f.f_bool:
        fail("frame decode")
    var point = Point(Int32(9), Int32(-4))
    same(encode_bytes(point), read_file("spec/golden/point.kiln"), "point")
    print("golden ok")
