from std.collections import Optional, Span

from Message import Message, Meta
from Point import Point
from kiln import Writer


def fail(msg: String) raises:
    raise Error(msg)


def main() raises:
    var p = Point()
    p.x = 3
    p.y = -1
    p.label = Optional[String](String("a"))
    var w = Writer()
    p.encode_to(w)
    if p.encoded_len() != w.length:
        fail("point len")
    var raw = w.copy_bytes()
    var back = Point.decode_from(Span(raw))
    if back.x != 3 or back.y != -1:
        fail("point values")
    if not back.label or back.label.value() != "a":
        fail("point label")

    var meta = Meta()
    meta.region = "us"
    meta.flag = True
    var m = Message()
    m.f_bool = True
    m.f_int32 = -2
    m.f_int64 = 99
    m.f_float64 = 1.5
    m.f_string = "hi"
    m.f_bool_2 = False
    m.f_int32_2 = 7
    m.f_string_2 = "z"
    m.meta = meta^
    var w2 = Writer()
    m.encode_to(w2)
    if m.encoded_len() != w2.length:
        fail("message len")
    var back_m = Message.decode_from(Span(w2.copy_bytes()))
    if back_m.f_string != "hi" or back_m.f_int32 != -2:
        fail("message values")
    if back_m.meta.region != "us" or not back_m.meta.flag:
        fail("meta")
    print("gen ok")
