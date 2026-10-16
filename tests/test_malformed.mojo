from std.collections import List, Span

from kiln import KilnError, decode_bytes, decode_framed, encode_bytes
from kiln.wire import Reader


@fieldwise_init
struct Point(Copyable, Movable, Defaultable):
    var x: Int32
    var y: Int32

    def __init__(out self):
        self.x = 0
        self.y = 0


def fail(msg: String) raises:
    raise Error(msg)


def _catch_point(data: List[UInt8]) -> String:
    try:
        _ = decode_bytes[Point](data)
        return ""
    except e:
        return String(e)


def expect_kind(data: List[UInt8], kind: Int, label: String) raises:
    var text = _catch_point(data)
    if text.byte_length() == 0:
        fail(label + " did not raise")
    if text.find("kind=" + String(kind)) < 0:
        fail(label + " -> " + text)


def put_u32(mut raw: List[UInt8], v: UInt32):
    raw.append(UInt8(v))
    raw.append(UInt8(v >> 8))
    raw.append(UInt8(v >> 16))
    raw.append(UInt8(v >> 24))


def test_truncated() raises:
    var raw = List[UInt8]()
    raw.append(UInt8(1))
    expect_kind(raw, KilnError.EOF, "truncated point")


def _catch_bool(data: List[UInt8]) -> String:
    try:
        _ = decode_bytes[Bool](data)
        return ""
    except e:
        return String(e)


def test_bad_bool() raises:
    var raw = encode_bytes(True)
    raw[0] = UInt8(2)
    var text = _catch_bool(raw)
    if text.find("kind=" + String(KilnError.TYPE)) < 0:
        fail("bad bool " + text)


def _catch_string(data: List[UInt8], check: Bool) -> String:
    try:
        _ = decode_bytes[String](data, check)
        return ""
    except e:
        return String(e)


def test_huge_length() raises:
    var raw = List[UInt8]()
    put_u32(raw, UInt32(0xFFFFFFFF))
    var text = _catch_string(raw, True)
    if text.find("kind=" + String(KilnError.LIMIT)) < 0 and text.find("kind=" + String(KilnError.EOF)) < 0:
        fail("huge length " + text)


def test_short_string() raises:
    var raw = List[UInt8]()
    put_u32(raw, UInt32(4))
    raw.append(UInt8(0x61))
    var text = _catch_string(raw, True)
    if text.find("kind=" + String(KilnError.EOF)) < 0:
        fail("short string " + text)


def test_bad_utf8() raises:
    var raw = List[UInt8]()
    put_u32(raw, UInt32(1))
    raw.append(UInt8(0xFF))
    var text = _catch_string(raw, True)
    if text.find("kind=" + String(KilnError.UTF8)) < 0:
        fail("bad utf8 " + text)
    var back = decode_bytes[String](raw, False)
    check_len(back)


def check_len(s: String) raises:
    if s.byte_length() != 1:
        raise Error("unchecked utf8 length")


def test_trailing() raises:
    var raw = encode_bytes(Int32(1))
    raw.append(UInt8(0))
    var text = String("")
    try:
        _ = decode_bytes[Int32](raw)
    except e:
        text = String(e)
    if text.find("kind=" + String(KilnError.TRAILING)) < 0:
        fail("trailing " + text)


def test_bad_frame() raises:
    var raw = List[UInt8]()
    var i = 0
    while i < 16:
        raw.append(UInt8(0))
        i += 1
    var text = String("")
    try:
        _ = decode_framed[Point](Span(raw))
    except e:
        text = String(e)
    if text.find("kind=" + String(KilnError.FRAME)) < 0:
        fail("bad frame " + text)


def test_view() raises:
    var raw = encode_bytes(String("hi"))
    var r = Reader(Span(raw))
    var sl = r.read_string_slice()
    if String(sl) != "hi":
        raise Error("view")
    if r.pos != len(raw):
        raise Error("view pos")


def test_hostile_count_does_not_allocate() raises:
    # A list count past the buffer must fail before any element allocation.
    var raw = List[UInt8]()
    put_u32(raw, UInt32(0x0FFFFFFF))
    var text = String("")
    try:
        _ = decode_bytes[List[Int32]](raw)
    except e:
        text = String(e)
    if text.find("kind=" + String(KilnError.EOF)) < 0 and text.find("kind=" + String(KilnError.LIMIT)) < 0:
        fail("hostile count " + text)


def main() raises:
    test_truncated()
    test_bad_bool()
    test_huge_length()
    test_short_string()
    test_bad_utf8()
    test_trailing()
    test_bad_frame()
    test_view()
    test_hostile_count_does_not_allocate()
    print("malformed ok")
