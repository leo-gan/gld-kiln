from std.collections import List, Span

from kiln import (
    DTYPE_BOOL,
    DTYPE_E2M1,
    DTYPE_E8M0,
    DTYPE_F16,
    DTYPE_F32,
    DTYPE_F8E4M3,
    DTYPE_F8E5M2,
    KilnError,
    KilnTensor,
    TensorDir,
    decode,
    decode_framed,
    encode_bytes,
    encode_framed,
    type_hash,
)
from kiln.wire import Writer


@fieldwise_init
struct OneI64(Copyable, Movable, Defaultable):
    var a: Int64

    def __init__(out self):
        self.a = 0


@fieldwise_init
struct IdBatch(Copyable, Movable, Defaultable):
    var id: Int64
    var batch: TensorDir

    def __init__(out self):
        self.id = 0
        self.batch = TensorDir()


def fail(msg: String) raises:
    raise Error(msg)


def put_u32(mut raw: List[UInt8], v: UInt32):
    raw.append(UInt8(v))
    raw.append(UInt8(v >> 8))
    raw.append(UInt8(v >> 16))
    raw.append(UInt8(v >> 24))


def kind_of[T: Defaultable & Movable & Deinitable](raw: List[UInt8]) -> Int:
    try:
        _ = decode[T](Span(raw))
        return 0
    except e:
        var text = String(e)
        if text.find("kind=" + String(KilnError.EOF)) >= 0:
            return KilnError.EOF
        if text.find("kind=" + String(KilnError.LIMIT)) >= 0:
            return KilnError.LIMIT
        if text.find("kind=" + String(KilnError.TYPE)) >= 0:
            return KilnError.TYPE
        if text.find("kind=" + String(KilnError.FRAME)) >= 0:
            return KilnError.FRAME
        if text.find("kind=" + String(KilnError.UTF8)) >= 0:
            return KilnError.UTF8
        if text.find("kind=" + String(KilnError.TRAILING)) >= 0:
            return KilnError.TRAILING
        return -1


def expect(raw: List[UInt8], want: Int, label: String) raises:
    var got = kind_of[TensorDir](raw)
    if got != want:
        fail(label + " kind " + String(got))


def byte_at(mut raw: List[UInt8], v: Int):
    raw.append(UInt8(v))


def empty_header(flags: Int, count: Int, name_bytes: Int, payload: UInt64, directory: UInt64) -> List[UInt8]:
    var raw = List[UInt8]()
    byte_at(raw, 0x4B)
    byte_at(raw, 0x4C)
    byte_at(raw, 0x4E)
    byte_at(raw, 0x54)
    byte_at(raw, 2)
    byte_at(raw, flags)
    byte_at(raw, 0)
    byte_at(raw, 0)
    put_u32(raw, UInt32(count))
    put_u32(raw, UInt32(name_bytes))
    var i = 0
    var p = payload
    while i < 8:
        raw.append(UInt8(p))
        p = p >> 8
        i += 1
    i = 0
    var d = directory
    while i < 8:
        raw.append(UInt8(d))
        d = d >> 8
        i += 1
    while len(raw) < 64:
        raw.append(UInt8(0))
    return raw^


def f32_vector() -> TensorDir:
    var shape = List[UInt64]()
    shape.append(UInt64(2))
    var data = List[UInt8]()
    data.append(UInt8(0x00))
    data.append(UInt8(0x00))
    data.append(UInt8(0x80))
    data.append(UInt8(0x3F))
    data.append(UInt8(0x00))
    data.append(UInt8(0x00))
    data.append(UInt8(0x00))
    data.append(UInt8(0xC0))
    var tensor = KilnTensor(DTYPE_F32, shape^, data^)
    var dir = TensorDir()
    dir.items.append(tensor^)
    return dir^


def test_empty() raises:
    var dir = TensorDir()
    var raw = encode_bytes(dir)
    if len(raw) != 64:
        fail("empty len " + String(len(raw)))
    if raw[4] != 2 or raw[5] != 2:
        fail("empty header")
    var back = decode[TensorDir](Span(raw))
    if len(back.items) != 0:
        fail("empty items")


def test_f32_roundtrip() raises:
    var dir = f32_vector()
    var raw = encode_bytes(dir)
    if len(raw) != 200:
        fail("f32 len " + String(len(raw)))
    if raw[192] != 0 or raw[194] != 0x80 or raw[195] != 0x3F:
        fail("f32 payload")
    if raw[196] != 0 or raw[199] != 0xC0:
        fail("f32 second")
    var back = decode[TensorDir](Span(raw))
    if len(back.items) != 1 or back.items[0].rank != 1:
        fail("f32 rank")
    if back.items[0].shape[0] != 2 or len(back.items[0].data) != 8:
        fail("f32 shape")
    if back.items[0].name != "":
        fail("f32 name")


def test_named_f16() raises:
    var shape = List[UInt64]()
    var data = List[UInt8]()
    data.append(UInt8(0x00))
    data.append(UInt8(0x3C))
    var tensor = KilnTensor(DTYPE_F16, shape^, data^)
    tensor.name = "w"
    var dir = TensorDir()
    dir.items.append(tensor^)
    var raw = encode_bytes(dir)
    var back = decode[TensorDir](Span(raw))
    if back.items[0].name != "w" or back.items[0].dtype != DTYPE_F16:
        fail("f16 name")
    if back.items[0].data[0] != 0 or back.items[0].data[1] != 0x3C:
        fail("f16 bits")


def test_frame_hash() raises:
    var batch = IdBatch()
    batch.id = 7
    var got = type_hash[IdBatch]()
    var want = (UInt64(0xE58AADC7) << 32) | UInt64(0x552F0D82)
    if got != want:
        fail("hash " + String(got))
    var w = Writer()
    encode_framed(batch, w)
    var raw = w.copy_bytes()
    var back = decode_framed[IdBatch](Span(raw))
    if back.id != 7 or len(back.batch.items) != 0:
        fail("framed value")


def test_in_struct() raises:
    var batch = IdBatch()
    batch.id = 7
    batch.batch = f32_vector()
    var raw = encode_bytes(batch)
    var back = decode[IdBatch](Span(raw))
    if back.id != 7 or len(back.batch.items) != 1:
        fail("struct")
    if back.batch.items[0].data[2] != 0x80:
        fail("struct payload")


def test_rejects() raises:
    var bad_magic = empty_header(2, 0, 0, 0, 0)
    bad_magic[0] = UInt8(0x58)
    expect(bad_magic^, KilnError.FRAME, "magic")
    var bad_version = empty_header(2, 0, 0, 0, 0)
    bad_version[4] = UInt8(1)
    expect(bad_version^, KilnError.FRAME, "version")
    var le = empty_header(0, 0, 0, 0, 0)
    expect(le^, KilnError.FRAME, "le")
    var named = empty_header(3, 0, 0, 0, 0)
    expect(named^, KilnError.TYPE, "empty name flag")
    var unknown = empty_header(6, 0, 0, 0, 0)
    expect(unknown^, KilnError.FRAME, "flag")
    var reserved = empty_header(2, 0, 0, 0, 0)
    reserved[32] = 1
    expect(reserved^, KilnError.FRAME, "reserved")
    var short = empty_header(2, 2, 0, 0, 256)
    expect(short^, KilnError.EOF, "directory eof")
    var huge = empty_header(2, 16777217, 0, 0, UInt64(16777217) * 128)
    expect(huge^, KilnError.LIMIT, "count cap")
    var overflow = empty_header(2, 0, 0, ~UInt64(0), 0)
    expect(overflow^, KilnError.LIMIT, "payload overflow")
    var trail = empty_header(2, 0, 0, 0, 0)
    trail.append(UInt8(0))
    expect(trail^, KilnError.TRAILING, "trailing")


def test_allocation() raises:
    var hostile = List[UInt8]()
    put_u32(hostile, UInt32(16777216))
    if kind_of[List[OneI64]](hostile^) != KilnError.EOF:
        fail("hostile struct list")
    var short = List[UInt8]()
    put_u32(short, UInt32(2))
    var i = 0
    while i < 8:
        short.append(UInt8(0))
        i += 1
    if kind_of[List[OneI64]](short^) != KilnError.EOF:
        fail("short struct list")
    var strings = List[UInt8]()
    put_u32(strings, UInt32(3))
    put_u32(strings, UInt32(0))
    if kind_of[List[String]](strings^) != KilnError.EOF:
        fail("short string list")
    var pods = List[UInt8]()
    put_u32(pods, UInt32(2))
    put_u32(pods, UInt32(0x3F800000))
    if kind_of[List[Float32]](pods^) != KilnError.EOF:
        fail("short f32 list")
    var ok = List[Float32]()
    ok.append(Float32(1.0))
    ok.append(Float32(-2.0))
    var back = decode[List[Float32]](Span(encode_bytes(ok)))
    if len(back) != 2 or back[0] != 1.0 or back[1] != -2.0:
        fail("f32 list roundtrip")


def test_scales_and_opaque() raises:
    var shape = List[UInt64]()
    shape.append(UInt64(32))
    var data = List[UInt8]()
    var i = 0
    while i < 16:
        data.append(UInt8(0))
        i += 1
    var values = KilnTensor(DTYPE_E2M1, shape^, data^)
    values.quant_scheme = 1
    values.quant_axis = 0
    values.group_size = 32
    values.scale_index = 1
    var scale_shape = List[UInt64]()
    scale_shape.append(UInt64(1))
    var scale_data = List[UInt8]()
    scale_data.append(UInt8(127))
    var scale = KilnTensor(DTYPE_E8M0, scale_shape^, scale_data^)
    var dir = TensorDir()
    dir.items.append(values^)
    dir.items.append(scale^)
    var back = decode[TensorDir](Span(encode_bytes(dir)))
    if back.items[0].quant_scheme != 1 or back.items[1].data[0] != 127:
        fail("scales")
    var opaque_shape = List[UInt64]()
    opaque_shape.append(UInt64(32))
    var opaque_data = List[UInt8]()
    i = 0
    while i < 18:
        opaque_data.append(UInt8(i))
        i += 1
    var opaque = KilnTensor(4096, opaque_shape^, opaque_data^)
    opaque.layout = "Q4_K"
    opaque.block_size = 18
    var bag = TensorDir()
    bag.items.append(opaque^)
    var got = decode[TensorDir](Span(encode_bytes(bag)))
    if got.items[0].layout != "Q4_K" or len(got.items[0].data) != 18:
        fail("opaque")


def test_bool_and_pair() raises:
    var shape = List[UInt64]()
    shape.append(UInt64(1))
    var data = List[UInt8]()
    data.append(UInt8(2))
    var bad = KilnTensor(DTYPE_BOOL, shape^, data^)
    var dir = TensorDir()
    dir.items.append(bad^)
    if kind_of[TensorDir](encode_bytes(dir)) != KilnError.TYPE:
        fail("bool byte")
    var a_shape = List[UInt64]()
    a_shape.append(UInt64(1))
    var a_data = List[UInt8]()
    a_data.append(UInt8(0x38))
    var b_shape = List[UInt64]()
    b_shape.append(UInt64(1))
    var b_data = List[UInt8]()
    b_data.append(UInt8(0x3C))
    var a = KilnTensor(DTYPE_F8E4M3, a_shape^, a_data^)
    var b = KilnTensor(DTYPE_F8E5M2, b_shape^, b_data^)
    var pair = TensorDir()
    pair.items.append(a^)
    pair.items.append(b^)
    var raw = encode_bytes(pair)
    var back = decode[TensorDir](Span(raw))
    if back.items[1].data[0] != 0x3C:
        fail("f8")


def main() raises:
    test_empty()
    test_f32_roundtrip()
    test_named_f16()
    test_frame_hash()
    test_in_struct()
    test_rejects()
    test_allocation()
    test_scales_and_opaque()
    test_bool_and_pair()
    print("tensor v2 ok")
