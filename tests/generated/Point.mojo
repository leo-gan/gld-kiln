from std.collections import Dict, List, Optional, Span

from kiln import Writer, decode, encode, encoded_size

@fieldwise_init
struct Point(Copyable, Movable, Defaultable):
    var x: Int32
    var y: Int32
    var label: Optional[String]

    def __init__(out self):
        self.x = 0
        self.y = 0
        self.label = Optional[String](None)

    def encoded_len(self) -> Int:
        return encoded_size(self)

    def encode_to(self, mut w: Writer) raises:
        encode(self, w)

    @staticmethod
    def decode_from[o: ImmOrigin](data: Span[UInt8, o]) raises -> Self:
        return decode[Self](data)

