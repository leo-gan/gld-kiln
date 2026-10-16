from std.collections import Dict, List, Optional, Span

from kiln import decode_bytes, encode, encode_bytes, encode_framed, encoded_size, type_hash
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


@fieldwise_init
struct Inner(Copyable, Movable, Defaultable):
    var n: Int32
    var s: String

    def __init__(out self):
        self.n = 0
        self.s = ""


@fieldwise_init
struct Outer(Copyable, Movable, Defaultable):
    var name: String
    var inner: Inner
    var tags: List[Int32]
    var note: Optional[String]

    def __init__(out self):
        self.name = ""
        self.inner = Inner()
        self.tags = List[Int32]()
        self.note = Optional[String](None)


def fail(msg: String) raises:
    raise Error(msg)


def hex_of(raw: List[UInt8]) -> String:
    var digits = "0123456789abcdef"
    var db = digits.as_bytes()
    var out = String()
    var i = 0
    while i < len(raw):
        var b = Int(raw[i])
        out = out + chr(Int(db[b >> 4]))
        out = out + chr(Int(db[b & 0xF]))
        i += 1
    return out


def check(cond: Bool, msg: String) raises:
    if not cond:
        fail(msg)


def test_scalars() raises:
    var b = encode_bytes(True)
    check(len(b) == 1 and b[0] == UInt8(1), "bool")
    var back_b = decode_bytes[Bool](b)
    check(back_b, "bool back")
    var n = encode_bytes(Int32(-2))
    check(hex_of(n) == "feffffff", "i32 -2")
    check(decode_bytes[Int32](n) == Int32(-2), "i32 back")
    var f = encode_bytes(Float64(1.5))
    check(hex_of(f) == "000000000000f83f", "f64 1.5")
    check(decode_bytes[Float64](f) == Float64(1.5), "f64 back")
    var s = encode_bytes(String("hi"))
    check(hex_of(s) == "020000006869", "str hi")
    check(decode_bytes[String](s) == "hi", "str back")
    var empty = encode_bytes(String(""))
    check(hex_of(empty) == "00000000", "empty str")
    var bits = Float64(from_bits=UInt64(0x7FF8000000000001))
    var fb = encode_bytes(bits)
    var got = decode_bytes[Float64](fb)
    check(UInt64(got.to_bits()) == UInt64(0x7FF8000000000001), "nan bits")


def test_message() raises:
    var m = Message(True, Int32(-2), Int64(99), Float64(1.5), "hi", False, Int32(7), "z")
    check(encoded_size(m) == 1 + 4 + 8 + 8 + 6 + 1 + 4 + 5, "message size")
    var raw = encode_bytes(m)
    check(len(raw) == encoded_size(m), "size matches")
    var back = decode_bytes[Message](raw)
    check(back.f_bool, "f_bool")
    check(back.f_int32 == Int32(-2), "f_int32")
    check(back.f_int64 == Int64(99), "f_int64")
    check(back.f_float64 == Float64(1.5), "f_float64")
    check(back.f_string == "hi", "f_string")
    check(not back.f_bool_2, "f_bool_2")
    check(back.f_int32_2 == Int32(7), "f_int32_2")
    check(back.f_string_2 == "z", "f_string_2")
    var w = Writer(8)
    encode(m, w)
    var first = w.length
    encode(Int32(1), w)
    check(w.length == 4 and first > 4, "writer reuse")
    check(len(w.buf) >= first, "capacity kept")


def test_nested() raises:
    var tags = List[Int32]()
    tags.append(Int32(3))
    tags.append(Int32(-1))
    var o = Outer("a", Inner(Int32(4), "bc"), tags^, Optional[String](String("n")))
    var raw = encode_bytes(o)
    var back = decode_bytes[Outer](raw)
    check(back.name == "a", "name")
    check(back.inner.n == Int32(4), "inner.n")
    check(back.inner.s == "bc", "inner.s")
    check(len(back.tags) == 2 and back.tags[0] == Int32(3) and back.tags[1] == Int32(-1), "tags")
    check(back.note.__bool__() and back.note.value() == "n", "note")
    var none_o = Outer("a", Inner(Int32(4), "bc"), List[Int32](), Optional[String](None))
    var raw2 = encode_bytes(none_o)
    var back2 = decode_bytes[Outer](raw2)
    check(not back2.note.__bool__(), "note none")
    check(len(back2.tags) == 0, "empty tags")


def test_dict() raises:
    var d = Dict[String, Int32]()
    d["b"] = Int32(2)
    d["a"] = Int32(1)
    var raw = encode_bytes(d)
    var back = decode_bytes[Dict[String, Int32]](raw)
    check(back["a"] == Int32(1) and back["b"] == Int32(2), "dict values")
    # Keys are lexicographic, so "a" precedes "b" on the wire.
    check(hex_of(raw).startswith("020000000100000061"), "dict order")


def test_bytes_list() raises:
    var xs = List[UInt8]()
    xs.append(UInt8(1))
    xs.append(UInt8(2))
    xs.append(UInt8(255))
    var raw = encode_bytes(xs)
    check(hex_of(raw) == "030000000102ff", "bytes")
    var back = decode_bytes[List[UInt8]](raw)
    check(len(back) == 3 and back[2] == UInt8(255), "bytes back")


def test_list_str() raises:
    var xs = List[String]()
    xs.append("a")
    xs.append("")
    var raw = encode_bytes(xs)
    var back = decode_bytes[List[String]](raw)
    check(len(back) == 2 and back[0] == "a" and back[1] == "", "list str")


def test_frame() raises:
    var h1 = type_hash[Point]()
    var h2 = type_hash[Point]()
    check(h1 == h2 and h1 != type_hash[Message](), "hash stable")
    var p = Point(Int32(9), Int32(-4))
    var w = Writer()
    encode_framed(p, w)
    var raw = w.copy_bytes()
    check(raw[0] == UInt8(0x4B) and raw[1] == UInt8(0x4C), "magic")
    var framed = decode_framed_point(raw)
    check(framed.x == Int32(9) and framed.y == Int32(-4), "framed")


def decode_framed_point(raw: List[UInt8]) raises -> Point:
    from kiln import decode_framed
    return decode_framed[Point](Span(raw))


def test_depth() raises:
    var o = Outer("a", Inner(Int32(1), "b"), List[Int32](), Optional[String](None))
    var raised = False
    try:
        _ = encode_bytes(o, 1)
    except:
        raised = True
    check(raised, "depth 1 rejects nested outer")


def main() raises:
    test_scalars()
    test_message()
    test_nested()
    test_dict()
    test_bytes_list()
    test_list_str()
    test_frame()
    test_depth()
    print("roundtrip ok")
