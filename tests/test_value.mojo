from std.collections import Span

from kiln import encode_bytes
from kiln.schema import schema_from_json
from kiln.value import decode_value, encode_value_bytes, Value


@fieldwise_init
struct Point(Copyable, Movable, Defaultable):
    var x: Int32
    var y: Int32

    def __init__(out self):
        self.x = 0
        self.y = 0


def fail(msg: String) raises:
    raise Error(msg)


def main() raises:
    var text = "{\"title\":\"Point\",\"type\":\"object\",\"properties\":{\"x\":{\"type\":\"integer\",\"format\":\"int32\"},\"y\":{\"type\":\"integer\",\"format\":\"int32\"}},\"required\":[\"x\",\"y\"]}"
    var schema = schema_from_json(text)
    var v = Value()
    var root = v.start_struct()
    v.push(root, v.add_i64(Int64(9)))
    v.push(root, v.add_i64(Int64(-4)))
    v.root = root
    var dyn = encode_value_bytes(schema, v)
    var typed = encode_bytes(Point(Int32(9), Int32(-4)))
    if len(dyn) != len(typed):
        fail("len " + String(len(dyn)) + " " + String(len(typed)))
    var i = 0
    while i < len(dyn):
        if dyn[i] != typed[i]:
            fail("byte " + String(i))
        i += 1
    var back = decode_value(schema, Span(dyn))
    if back.nodes[back.root].nchild != 2:
        fail("children")
    var x = back.child(back.root, 0)
    var bits = back.words[back.nodes[x].a]
    if Int64(from_bits=bits) != Int64(9):
        fail("x")
    var y = back.child(back.root, 1)
    if Int64(from_bits=back.words[back.nodes[y].a]) != Int64(-4):
        fail("y")
    print("value ok")
