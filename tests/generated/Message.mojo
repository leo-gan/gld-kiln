from std.collections import Dict, List, Optional, Span

from kiln import Writer, decode, encode, encoded_size

@fieldwise_init
struct Meta(Copyable, Movable, Defaultable):
    var region: String
    var flag: Bool

    def __init__(out self):
        self.region = String("")
        self.flag = False

    def encoded_len(self) -> Int:
        return encoded_size(self)

    def encode_to(self, mut w: Writer) raises:
        encode(self, w)

    @staticmethod
    def decode_from[o: ImmOrigin](data: Span[UInt8, o]) raises -> Self:
        return decode[Self](data)

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
    var meta: Meta

    def __init__(out self):
        self.f_bool = False
        self.f_int32 = 0
        self.f_int64 = 0
        self.f_float64 = 0.0
        self.f_string = String("")
        self.f_bool_2 = False
        self.f_int32_2 = 0
        self.f_string_2 = String("")
        self.meta = Meta()

    def encoded_len(self) -> Int:
        return encoded_size(self)

    def encode_to(self, mut w: Writer) raises:
        encode(self, w)

    @staticmethod
    def decode_from[o: ImmOrigin](data: Span[UInt8, o]) raises -> Self:
        return decode[Self](data)

