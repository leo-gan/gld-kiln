from std.collections import List

from kiln import decode_bytes, encode_bytes


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


def word(state: Int) -> String:
    var n = state & 15
    var s = String()
    var i = 0
    while i < n:
        s = s + chr(97 + ((state + i) & 15))
        i += 1
    return s


def main() raises:
    var state = 1
    var i = 0
    while i < 50:
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF
        var m = Message()
        m.f_bool = (state & 1) == 1
        m.f_int32 = Int32(state - 1000)
        m.f_int64 = Int64(state) * Int64(3) - Int64(20)
        m.f_float64 = Float64(state) * 0.125
        m.f_string = word(state)
        m.f_bool_2 = (state & 2) == 2
        m.f_int32_2 = Int32(-(state & 255))
        m.f_string_2 = word(state >> 3)
        var raw = encode_bytes(m)
        var back = decode_bytes[Message](raw)
        if back.f_bool != m.f_bool or back.f_int32 != m.f_int32 or back.f_int64 != m.f_int64:
            fail("fuzz scalar " + String(i))
        if back.f_string != m.f_string or back.f_string_2 != m.f_string_2:
            fail("fuzz string " + String(i))
        if back.f_float64 != m.f_float64 or back.f_int32_2 != m.f_int32_2 or back.f_bool_2 != m.f_bool_2:
            fail("fuzz tail " + String(i))
        i += 1
    var junk = List[UInt8]()
    var k = 0
    while k < 32:
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF
        junk.append(UInt8(state))
        try:
            _ = decode_bytes[Message](junk)
        except:
            i = i
        k += 1
    print("fuzz ok")
