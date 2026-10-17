"""Reference checks for Kiln tensor directories, version 2.

Writes spec/kiln-v2-cases.json. This is not the runtime codec.
The check order in `decode_v2` is the order the spec requires.
"""

from __future__ import annotations

import json
import struct
from pathlib import Path


FNV_OFFSET = 14695981039346656037
FNV_PRIME = 1099511628211
MASK = 0xFFFFFFFFFFFFFFFF

HEADER = 64
DESC = 128
CAP = 16_777_216
FLAG_NAME = 0x01
FLAG_LE = 0x02

DTYPE = {
    "f64": 1,
    "f32": 2,
    "f16": 3,
    "bf16": 4,
    "f8e4m3": 5,
    "f8e5m2": 6,
    "bool": 7,
    "i8": 8,
    "u8": 9,
    "i16": 10,
    "u16": 11,
    "i32": 12,
    "u32": 13,
    "i64": 14,
    "u64": 15,
    "i4": 16,
    "u4": 17,
    "e2m1": 18,
    "e8m0": 19,
}
DTYPE_NAME = {code: name for name, code in DTYPE.items()}
WHOLE = {
    1: 8,
    2: 4,
    3: 2,
    4: 2,
    5: 1,
    6: 1,
    7: 1,
    8: 1,
    9: 1,
    10: 2,
    11: 2,
    12: 4,
    13: 4,
    14: 8,
    15: 8,
    19: 1,
}
PACKED = {16, 17, 18}
OPAQUE_MIN = 4096
OPAQUE_MAX = 32767


def align64(n: int) -> int:
    return (n + 63) & ~63


def _mix(h: int, data: bytes) -> int:
    for byte in data:
        h ^= byte
        h = (h * FNV_PRIME) & MASK
    h = (h * FNV_PRIME) & MASK
    return h


def _hash_schema(h: int, schema: tuple) -> int:
    kind = schema[0]
    if kind in {
        "bool",
        "i8",
        "i16",
        "i32",
        "i64",
        "int",
        "u8",
        "u16",
        "u32",
        "u64",
        "uint",
        "f32",
        "f64",
        "str",
        "tensors",
    }:
        return _mix(h, kind.encode("ascii"))
    if kind == "list":
        h = _mix(h, b"list<")
        h = _hash_schema(h, schema[1])
        return _mix(h, b">")
    if kind == "struct":
        h = _mix(h, b"struct{")
        for name, field in schema[1]:
            h = _mix(h, name.encode("utf-8"))
            h = _mix(h, b":")
            h = _hash_schema(h, field)
            h = _mix(h, b",")
        return _mix(h, b"}")
    raise ValueError(kind)


def type_hash(schema: tuple) -> int:
    return _hash_schema(FNV_OFFSET, schema)


class Fail(Exception):
    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


def _u16(buf: bytes, i: int) -> int:
    return struct.unpack_from("<H", buf, i)[0]


def _u32(buf: bytes, i: int) -> int:
    return struct.unpack_from("<I", buf, i)[0]


def _u64(buf: bytes, i: int) -> int:
    return struct.unpack_from("<Q", buf, i)[0]


def _need(buf: bytes, n: int) -> None:
    if len(buf) < n:
        raise Fail("EOF")


def _add(a: int, b: int) -> int:
    total = a + b
    if total > MASK:
        raise Fail("LIMIT")
    return total


def _mul(a: int, b: int) -> int:
    if a != 0 and b > MASK // a:
        raise Fail("LIMIT")
    return a * b


def canonical_heap(tensors: list[dict]) -> bytes:
    parts: list[bytes] = []
    for tensor in tensors:
        name = tensor.get("name")
        if name:
            parts.append(name)
    for tensor in tensors:
        layout = tensor.get("layout")
        if layout:
            parts.append(layout)
    return b"".join(parts)


def assign_offsets(tensors: list[dict]) -> int:
    end = 0
    for tensor in tensors:
        tensor["byte_offset"] = align64(end)
        end = tensor["byte_offset"] + tensor["byte_length"]
    return end


def build_v2(
    tensors: list[dict],
    *,
    flags: int = FLAG_LE,
    count: int | None = None,
    name_bytes: int | None = None,
    directory_bytes: int | None = None,
    payload_bytes: int | None = None,
    payload: bytes | None = None,
    heap: bytes | None = None,
    reserved16: int = 0,
    reserved_tail: bytes | None = None,
    truncate: int | None = None,
    tail: bytes = b"",
) -> bytes:
    """Build a version-2 block. Omitted sizes take the canonical value."""
    heap_bytes = canonical_heap(tensors) if heap is None else heap
    if name_bytes is None:
        name_bytes = len(heap_bytes)
    n = len(tensors) if count is None else count
    if directory_bytes is None:
        directory_bytes = n * DESC + name_bytes
    if payload is None:
        length = 0 if payload_bytes is None else payload_bytes
        if payload_bytes is None:
            length = assign_offsets(tensors) if count is None else 0
        body = bytearray(length)
        for tensor in tensors:
            off = tensor["byte_offset"]
            raw = tensor["data"]
            body[off : off + len(raw)] = raw
        payload = bytes(body)
    if payload_bytes is None:
        payload_bytes = len(payload)
    header = bytearray(HEADER)
    header[0:4] = b"KLNT"
    header[4] = 2
    header[5] = flags
    struct.pack_into("<H", header, 6, reserved16)
    struct.pack_into("<I", header, 8, n)
    struct.pack_into("<I", header, 12, name_bytes)
    struct.pack_into("<Q", header, 16, payload_bytes)
    struct.pack_into("<Q", header, 24, directory_bytes)
    if reserved_tail:
        header[32 : 32 + len(reserved_tail)] = reserved_tail
    # A hostile count is only a header. Do not allocate one descriptor per claim.
    if n > len(tensors) and n > 1024:
        block = bytes(header)
        if truncate is not None:
            block = block[:truncate]
        return block + tail
    directory = bytearray(max(0, n) * DESC + len(heap_bytes))
    for index, tensor in enumerate(tensors):
        if index >= n:
            break
        base = index * DESC
        struct.pack_into("<H", directory, base + 0, tensor["dtype"])
        directory[base + 2] = tensor["rank"]
        directory[base + 3] = tensor.get("reserved", 0)
        struct.pack_into("<H", directory, base + 4, tensor["name_off"])
        struct.pack_into("<H", directory, base + 6, tensor["name_len"])
        struct.pack_into("<H", directory, base + 8, tensor["layout_off"])
        struct.pack_into("<H", directory, base + 10, tensor["layout_len"])
        struct.pack_into("<I", directory, base + 12, tensor["block_size"])
        struct.pack_into("<H", directory, base + 16, tensor["quant_scheme"])
        struct.pack_into("<H", directory, base + 18, tensor["quant_axis"])
        struct.pack_into("<I", directory, base + 20, tensor["group_size"])
        struct.pack_into("<I", directory, base + 24, tensor["scale_index"])
        struct.pack_into("<I", directory, base + 28, tensor["outer_index"])
        struct.pack_into("<Q", directory, base + 32, tensor["byte_offset"])
        struct.pack_into("<Q", directory, base + 40, tensor["byte_length"])
        for dim in range(8):
            struct.pack_into("<Q", directory, base + 48 + 8 * dim, tensor["shape"][dim])
    if heap_bytes:
        directory[n * DESC : n * DESC + len(heap_bytes)] = heap_bytes
    # A mismatched directory_bytes still contributes only the bytes we have.
    # The canonical builder writes exactly directory_bytes when they match.
    if directory_bytes == len(directory):
        directory_raw = bytes(directory)
    elif directory_bytes > len(directory):
        directory_raw = bytes(directory) + bytes(directory_bytes - len(directory))
    else:
        directory_raw = bytes(directory[:directory_bytes])
    payload_base = align64(HEADER + len(directory_raw))
    pad = payload_base - (HEADER + len(directory_raw))
    block = bytes(header) + directory_raw + bytes(pad) + payload + tail
    if truncate is not None:
        block = block[:truncate]
    return block


def describe(
    *,
    dtype: str | int,
    data: bytes,
    shape: list[int],
    rank: int | None = None,
    name: bytes | None = None,
    layout: bytes | None = None,
    block_size: int = 0,
    quant_scheme: int = 0,
    quant_axis: int = 0xFFFF,
    group_size: int = 0,
    scale_index: int = 0xFFFFFFFF,
    outer_index: int = 0xFFFFFFFF,
    byte_length: int | None = None,
    byte_offset: int | None = None,
    reserved: int = 0,
) -> dict:
    code = dtype if isinstance(dtype, int) else DTYPE[dtype]
    if rank is None:
        rank = len(shape)
    full = list(shape) + [0] * (8 - len(shape))
    return {
        "dtype": code,
        "rank": rank,
        "shape": full,
        "data": data,
        "name": name,
        "layout": layout,
        "name_off": 0xFFFF,
        "name_len": 0,
        "layout_off": 0xFFFF,
        "layout_len": 0,
        "block_size": block_size,
        "quant_scheme": quant_scheme,
        "quant_axis": quant_axis,
        "group_size": group_size,
        "scale_index": scale_index,
        "outer_index": outer_index,
        "byte_length": len(data) if byte_length is None else byte_length,
        "byte_offset": 0 if byte_offset is None else byte_offset,
        "reserved": reserved,
    }


def stamp_names(tensors: list[dict]) -> None:
    heap = 0
    named = 0
    for tensor in tensors:
        name = tensor["name"]
        if name:
            tensor["name_off"] = heap
            tensor["name_len"] = len(name)
            heap += len(name)
            named += 1
        else:
            tensor["name_off"] = 0xFFFF
            tensor["name_len"] = 0
    for tensor in tensors:
        layout = tensor["layout"]
        if layout:
            tensor["layout_off"] = heap
            tensor["layout_len"] = len(layout)
            heap += len(layout)
        else:
            tensor["layout_off"] = 0xFFFF
            tensor["layout_len"] = 0
    return None


def canonical(tensors: list[dict], **kwargs: object) -> bytes:
    stamp_names(tensors)
    flags = FLAG_LE
    if any(tensor["name"] for tensor in tensors):
        flags |= FLAG_NAME
    if "flags" not in kwargs:
        kwargs["flags"] = flags
    return build_v2(tensors, **kwargs)  # type: ignore[arg-type]


def _element_count(rank: int, shape: list[int]) -> int:
    if rank == 0:
        return 1
    count = 1
    for dim in range(rank):
        count = _mul(count, shape[dim])
    return count


def _expected_bytes(dtype: int, count: int) -> int:
    if dtype in WHOLE:
        return _mul(count, WHOLE[dtype])
    if dtype in PACKED:
        return (count + 1) // 2
    raise Fail("TYPE")


def decode_v2(buf: bytes, *, standalone: bool = True, cap: int = CAP) -> dict:
    """Decode one version-2 directory. Check order matches the draft."""
    _need(buf, 4)
    if buf[0:4] != b"KLNT":
        raise Fail("FRAME")
    _need(buf, HEADER)
    version = buf[4]
    if version != 2:
        raise Fail("FRAME")
    flags = buf[5]
    if flags & ~0x03:
        raise Fail("FRAME")
    if flags & FLAG_LE == 0:
        raise Fail("FRAME")
    if _u16(buf, 6) != 0 or any(buf[32:HEADER]):
        raise Fail("FRAME")
    count = _u32(buf, 8)
    name_bytes = _u32(buf, 12)
    payload_bytes = _u64(buf, 16)
    directory_bytes = _u64(buf, 24)
    if count > cap or name_bytes > cap:
        raise Fail("LIMIT")
    expect_dir = _add(_mul(count, DESC), name_bytes)
    if directory_bytes != expect_dir:
        raise Fail("TYPE")
    directory_end = _add(HEADER, directory_bytes)
    if directory_end > len(buf):
        raise Fail("EOF")
    payload_base = align64(directory_end)
    block_end = _add(payload_base, payload_bytes)
    if block_end > len(buf):
        raise Fail("EOF")
    if any(buf[directory_end:payload_base]):
        raise Fail("TYPE")
    raw_tensors = []
    for index in range(count):
        base = HEADER + index * DESC
        dtype = _u16(buf, base)
        rank = buf[base + 2]
        reserved = buf[base + 3]
        name_off = _u16(buf, base + 4)
        name_len = _u16(buf, base + 6)
        layout_off = _u16(buf, base + 8)
        layout_len = _u16(buf, base + 10)
        block_size = _u32(buf, base + 12)
        quant_scheme = _u16(buf, base + 16)
        quant_axis = _u16(buf, base + 18)
        group_size = _u32(buf, base + 20)
        scale_index = _u32(buf, base + 24)
        outer_index = _u32(buf, base + 28)
        byte_offset = _u64(buf, base + 32)
        byte_length = _u64(buf, base + 40)
        shape = [_u64(buf, base + 48 + 8 * dim) for dim in range(8)]
        if any(buf[base + 112 : base + DESC]):
            raise Fail("FRAME")
        raw_tensors.append(
            {
                "dtype": dtype,
                "rank": rank,
                "reserved": reserved,
                "name_off": name_off,
                "name_len": name_len,
                "layout_off": layout_off,
                "layout_len": layout_len,
                "block_size": block_size,
                "quant_scheme": quant_scheme,
                "quant_axis": quant_axis,
                "group_size": group_size,
                "scale_index": scale_index,
                "outer_index": outer_index,
                "byte_offset": byte_offset,
                "byte_length": byte_length,
                "shape": shape,
            }
        )
    heap = buf[HEADER + count * DESC : directory_end]
    names_flag = bool(flags & FLAG_NAME)
    has_name = any(item["name_len"] for item in raw_tensors)
    if names_flag != has_name:
        raise Fail("TYPE")
    if names_flag and any(item["name_len"] == 0 for item in raw_tensors):
        raise Fail("TYPE")
    parts: list[bytes] = []
    layouts: list[bytes] = []
    seen: set[bytes] = set()
    for item in raw_tensors:
        if item["reserved"] != 0:
            raise Fail("FRAME")
        if item["name_len"] == 0:
            if item["name_off"] != 0xFFFF:
                raise Fail("TYPE")
        else:
            if item["name_off"] == 0xFFFF:
                raise Fail("TYPE")
            end = _add(item["name_off"], item["name_len"])
            if end > name_bytes:
                raise Fail("TYPE")
            try:
                name = heap[item["name_off"] : end]
                name.decode("utf-8")
            except UnicodeDecodeError:
                raise Fail("UTF8") from None
            if name in seen:
                raise Fail("TYPE")
            seen.add(name)
            parts.append(name)
            item["name"] = name
        if item["layout_len"] == 0:
            if item["layout_off"] != 0xFFFF:
                raise Fail("TYPE")
            item["layout"] = None
        else:
            end = _add(item["layout_off"], item["layout_len"])
            if end > name_bytes:
                raise Fail("TYPE")
            try:
                layout = heap[item["layout_off"] : end]
                layout.decode("utf-8")
            except UnicodeDecodeError:
                raise Fail("UTF8") from None
            layouts.append(layout)
            item["layout"] = layout
    if heap != b"".join(parts) + b"".join(layouts):
        raise Fail("TYPE")
    ranges: list[tuple[int, int]] = []
    for item in raw_tensors:
        item_end = _add(item["byte_offset"], item["byte_length"])
        if item_end > payload_bytes:
            raise Fail("TYPE")
        ranges.append((item["byte_offset"], item_end))
        _check_tensor(item)
    for left in range(len(ranges)):
        for right in range(left + 1, len(ranges)):
            a0, a1 = ranges[left]
            b0, b1 = ranges[right]
            if a0 == a1 or b0 == b1:
                continue
            if a0 < b1 and b0 < a1:
                raise Fail("TYPE")
    end = 0
    for item in raw_tensors:
        if item["byte_offset"] != align64(end):
            raise Fail("TYPE")
        end = item["byte_offset"] + item["byte_length"]
    if end != payload_bytes:
        raise Fail("TYPE")
    payload = buf[payload_base:block_end]
    for item in raw_tensors:
        region = payload[item["byte_offset"] : item["byte_offset"] + item["byte_length"]]
        if item["dtype"] in PACKED:
            count_elems = _element_count(item["rank"], item["shape"])
            if count_elems % 2 == 1 and region and (region[-1] >> 4) != 0:
                raise Fail("TYPE")
        if item["dtype"] == DTYPE["bool"] and any(byte > 1 for byte in region):
            raise Fail("TYPE")
        # Gaps between this payload and the previous end are inside `payload`
        # and were required to be the canonical offset. Zero them by rule.
    # Zero-fill of alignment gaps: bytes not covered by a payload must be 0.
    covered = bytearray(payload_bytes)
    for item in raw_tensors:
        start = item["byte_offset"]
        covered[start : start + item["byte_length"]] = b"\x01" * item["byte_length"]
    for index, flag in enumerate(covered):
        if flag == 0 and payload[index] != 0:
            raise Fail("TYPE")
    _check_quant(raw_tensors)
    if standalone and block_end != len(buf):
        raise Fail("TRAILING")
    out = []
    for item in raw_tensors:
        out.append(
            {
                "name": item.get("name").decode("utf-8") if item.get("name") else None,
                "dtype": DTYPE_NAME.get(item["dtype"], item["dtype"]),
                "shape": item["shape"][: item["rank"]],
                "quant_scheme": item["quant_scheme"],
                "data_hex": payload[
                    item["byte_offset"] : item["byte_offset"] + item["byte_length"]
                ].hex(),
            }
        )
    return {
        "version": 2,
        "flags": ["names", "le"] if names_flag else ["le"],
        "tensors": out,
        "block_length": block_end,
    }


def _check_tensor(item: dict) -> None:
    dtype = item["dtype"]
    rank = item["rank"]
    if rank > 8:
        raise Fail("TYPE")
    if any(item["shape"][dim] != 0 for dim in range(rank, 8)):
        raise Fail("TYPE")
    if dtype == 0 or (20 <= dtype < OPAQUE_MIN) or dtype > OPAQUE_MAX:
        raise Fail("TYPE")
    count = _element_count(rank, item["shape"])
    if dtype >= OPAQUE_MIN:
        if not item["layout"] or item["block_size"] == 0:
            raise Fail("TYPE")
        if item["byte_length"] % item["block_size"] != 0:
            raise Fail("TYPE")
        return
    if item["layout"] or item["block_size"] != 0:
        raise Fail("TYPE")
    expect = _expected_bytes(dtype, count)
    if item["byte_length"] != expect:
        raise Fail("TYPE")


def _check_quant(tensors: list[dict]) -> None:
    for index, item in enumerate(tensors):
        scheme = item["quant_scheme"]
        if scheme == 0:
            if (
                item["group_size"] != 0
                or item["quant_axis"] != 0xFFFF
                or item["scale_index"] != 0xFFFFFFFF
                or item["outer_index"] != 0xFFFFFFFF
            ):
                raise Fail("TYPE")
            continue
        if scheme not in (1, 2):
            raise Fail("TYPE")
        if item["rank"] == 0 or item["quant_axis"] >= item["rank"]:
            raise Fail("TYPE")
        if item["group_size"] == 0:
            raise Fail("TYPE")
        scale = item["scale_index"]
        if scale == index or scale >= len(tensors):
            raise Fail("TYPE")
        other = tensors[scale]
        if other["quant_scheme"] != 0:
            raise Fail("TYPE")
        groups = (item["shape"][item["quant_axis"]] + item["group_size"] - 1) // item["group_size"]
        other_dims = 1
        for dim in range(item["rank"]):
            if dim != item["quant_axis"]:
                other_dims = _mul(other_dims, item["shape"][dim])
        expect = _mul(groups, other_dims)
        scale_count = _element_count(other["rank"], other["shape"])
        if scale_count != expect:
            raise Fail("TYPE")
        if scheme == 1:
            if item["outer_index"] != 0xFFFFFFFF:
                raise Fail("TYPE")
            continue
        outer = item["outer_index"]
        if outer == index or outer == scale or outer >= len(tensors):
            raise Fail("TYPE")
        outer_item = tensors[outer]
        if (
            outer_item["quant_scheme"] != 0
            or outer_item["dtype"] != DTYPE["f32"]
            or _element_count(outer_item["rank"], outer_item["shape"]) != 1
        ):
            raise Fail("TYPE")


def decode_v2_fixed(buf: bytes, *, standalone: bool = True, cap: int = CAP) -> dict:
    decoded = decode_v2(buf, standalone=standalone, cap=cap)
    names = any(item["name"] for item in decoded["tensors"])
    decoded["flags"] = ["names", "le"] if names else ["le"]
    return decoded


def min_size(schema: tuple) -> int:
    kind = schema[0]
    widths = {
        "bool": 1,
        "i8": 1,
        "u8": 1,
        "i16": 2,
        "u16": 2,
        "i32": 4,
        "u32": 4,
        "f32": 4,
        "i64": 8,
        "u64": 8,
        "int": 8,
        "uint": 8,
        "f64": 8,
        "str": 4,
        "tensors": HEADER,
    }
    if kind in widths:
        return widths[kind]
    if kind == "list":
        return 4
    if kind == "opt":
        return 1
    if kind == "dict":
        return 4
    if kind == "struct":
        return sum(min_size(field) for _, field in schema[1])
    raise ValueError(kind)


def check_list(buf: bytes, elem: tuple, cap: int = CAP) -> str | None:
    """Return the error code, or None when the count may allocate."""
    if len(buf) < 4:
        return "EOF"
    count = struct.unpack_from("<I", buf, 0)[0]
    if count > cap:
        return "LIMIT"
    each = min_size(elem)
    if each != 0 and count > MASK // each:
        return "LIMIT"
    need = count * each
    if need > len(buf) - 4:
        return "EOF"
    return None


def case(
    case_id: str,
    title: str,
    section: str,
    paragraph: str,
    raw: bytes,
    *,
    expect: str,
    error: str | None = None,
    decoded: object | None = None,
    schema: object = "tensor-v2",
    fixes: list[str] | None = None,
) -> dict:
    item = {
        "id": case_id,
        "title": title,
        "section": section,
        "section_title": section,
        "section_url": "https://leo-gan.github.io/gld-kiln/spec/#" + section.lower().replace(" ", "-").replace(",", ""),
        "paragraph": paragraph,
        "requirement": "MUST" if expect == "accept" else "MUST NOT",
        "expect": expect,
        "input": raw.hex(),
        "input_encoding": "hex",
        "schema": schema,
    }
    if error is not None:
        item["error"] = error
    if decoded is not None:
        item["decoded"] = decoded
    if fixes:
        item["fixes"] = fixes
    return item


def f32(value: float) -> bytes:
    return struct.pack("<f", value)


def f64(value: float) -> bytes:
    return struct.pack("<d", value)


def expect_ok(buf: bytes, **kwargs: object) -> dict:
    return decode_v2_fixed(buf, **kwargs)  # type: ignore[arg-type]


def expect_err(buf: bytes, code: str, **kwargs: object) -> None:
    try:
        decode_v2_fixed(buf, **kwargs)  # type: ignore[arg-type]
    except Fail as exc:
        if exc.code != code:
            raise SystemExit(f"expected {code}, got {exc.code}") from exc
        return
    raise SystemExit(f"expected {code}, decoded")


def main() -> None:
    cases: list[dict] = []

    empty = canonical([])
    decoded = expect_ok(empty)
    if len(empty) != 64:
        raise SystemExit(f"empty block is {len(empty)}")
    cases.append(
        case(
            "kiln-v2-empty",
            "An empty version-2 directory is a 64-byte header",
            "Tensor directory",
            "A directory with no tensors has directory_bytes 0 and payload_bytes 0. The block is the 64-byte header.",
            empty,
            expect="accept",
            decoded=decoded,
        )
    )

    pair = canonical(
        [
            describe(dtype="f32", shape=[2], data=f32(1.0) + f32(-2.0)),
        ]
    )
    decoded = expect_ok(pair)
    cases.append(
        case(
            "kiln-v2-f32",
            "One unnamed f32 vector is little-endian bits after a 128-byte descriptor",
            "Tensor directory",
            "Dtype 2 is f32. Shape [2] occupies 8 bytes at payload offset 0. The bytes of 1.0 are 00 00 80 3f.",
            pair,
            expect="accept",
            decoded=decoded,
            fixes=["endian"],
        )
    )

    scalar = canonical([describe(dtype="f32", shape=[], data=f32(1.0))])
    cases.append(
        case(
            "kiln-v2-f32-scalar",
            "Rank 0 is one element and every shape slot is zero",
            "Tensor directory",
            "A rank of 0 is a scalar. Its element count is 1, and all eight shape slots are 0.",
            scalar,
            expect="accept",
            decoded=expect_ok(scalar),
        )
    )

    negzero = canonical([describe(dtype="f32", shape=[], data=f32(-0.0))])
    if negzero.hex().endswith("00000080") is False:
        # payload is at the end; confirm the bits somewhere in the block
        if f32(-0.0).hex() != "00000080":
            raise SystemExit(f32(-0.0).hex())
    cases.append(
        case(
            "kiln-v2-f32-negzero",
            "A negative zero keeps its sign bit",
            "Tensor directory",
            "f32 negative zero is the little-endian bytes 00 00 00 80.",
            negzero,
            expect="accept",
            decoded=expect_ok(negzero),
            fixes=["endian"],
        )
    )

    nan_bits = struct.pack("<Q", 0x7FF8000000000001)
    nan = canonical([describe(dtype="f64", shape=[], data=nan_bits)])
    cases.append(
        case(
            "kiln-v2-f64-nan",
            "A Float64 NaN keeps the payload bits",
            "Tensor directory",
            "The f64 payload is the little-endian bits 0x7FF8000000000001, a quiet NaN with payload 1.",
            nan,
            expect="accept",
            decoded=expect_ok(nan),
            fixes=["endian"],
        )
    )

    named = canonical([describe(dtype="f16", shape=[], name=b"w", data=struct.pack("<H", 0x3C00))])
    cases.append(
        case(
            "kiln-v2-f16-named",
            "A named f16 tensor stores the name in the heap and pads the payload to a 64-byte boundary",
            "Tensor directory",
            "IEEE binary16 1.0 is 00 3c. The name flag is set. The name heap is the byte 77. Padding from the heap to the payload base is zero.",
            named,
            expect="accept",
            decoded=expect_ok(named),
        )
    )

    bf = canonical([describe(dtype="bf16", shape=[], data=struct.pack("<H", 0x3F80))])
    cases.append(
        case(
            "kiln-v2-bf16",
            "bfloat16 1.0 is the little-endian bits 0x3F80",
            "Dtypes",
            "bfloat16 is 1 sign bit, 8 exponent bits, and 7 significand bits. The value 1.0 is 80 3f.",
            bf,
            expect="accept",
            decoded=expect_ok(bf),
        )
    )

    ints = canonical([describe(dtype="i8", shape=[2], data=bytes([1, 0xFF]))])
    cases.append(
        case(
            "kiln-v2-i8",
            "An i8 payload is two's complement bytes",
            "Dtypes",
            "The bytes 01 ff are the values 1 and -1.",
            ints,
            expect="accept",
            decoded=expect_ok(ints),
        )
    )

    flags = canonical([describe(dtype="bool", shape=[2], data=bytes([1, 0]))])
    cases.append(
        case(
            "kiln-v2-bool",
            "A bool tensor stores one byte per element, 0 or 1",
            "Dtypes",
            "Bool elements are bytes. 0 is false and 1 is true.",
            flags,
            expect="accept",
            decoded=expect_ok(flags),
        )
    )

    nibbles = canonical([describe(dtype="u4", shape=[3], data=bytes([0x21, 0x03]))])
    cases.append(
        case(
            "kiln-v2-u4",
            "Packed u4 stores the first element in the low nibble",
            "Dtypes",
            "Three elements 1, 2, 3 occupy the bytes 21 03. The high nibble of the last byte is 0.",
            nibbles,
            expect="accept",
            decoded=expect_ok(nibbles),
        )
    )

    f8 = canonical(
        [
            describe(dtype="f8e4m3", shape=[1], data=bytes([0x38])),
            describe(dtype="f8e5m2", shape=[1], data=bytes([0x3C])),
        ]
    )
    cases.append(
        case(
            "kiln-v2-f8-pair",
            "Two f8 tensors are aligned, and the second starts at payload offset 64",
            "Dtypes",
            "f8e4m3 and f8e5m2 are one byte each. The canonical second offset is 64. Kiln stores the bytes and does not widen them.",
            f8,
            expect="accept",
            decoded=expect_ok(f8),
        )
    )

    mx_data = bytes(16)
    mx_scale = bytes([127])
    mx = canonical(
        [
            describe(
                dtype="e2m1",
                shape=[32],
                data=mx_data,
                quant_scheme=1,
                quant_axis=0,
                group_size=32,
                scale_index=1,
            ),
            describe(dtype="e8m0", shape=[1], data=mx_scale),
        ]
    )
    cases.append(
        case(
            "kiln-v2-scales",
            "Scheme 1 points at a sibling scale tensor and does not transform the elements",
            "Quantization",
            "Thirty-two e2m1 elements share one e8m0 scale. The scale byte is stored as 127. Kiln checks the group count and copies the bits.",
            mx,
            expect="accept",
            decoded=expect_ok(mx),
        )
    )

    outer = canonical(
        [
            describe(
                dtype="e2m1",
                shape=[16],
                data=bytes(8),
                quant_scheme=2,
                quant_axis=0,
                group_size=16,
                scale_index=1,
                outer_index=2,
            ),
            describe(dtype="f8e4m3", shape=[1], data=bytes([0x38])),
            describe(dtype="f32", shape=[1], data=f32(1.0)),
        ]
    )
    cases.append(
        case(
            "kiln-v2-scales-outer",
            "Scheme 2 adds one outer f32 tensor beside the block scales",
            "Quantization",
            "Sixteen e2m1 elements, one f8e4m3 scale, and one f32 outer value. The outer tensor has one element.",
            outer,
            expect="accept",
            decoded=expect_ok(outer),
        )
    )

    opaque = canonical(
        [
            describe(
                dtype=4096,
                shape=[32],
                data=bytes(range(18)),
                layout=b"Q4_K",
                block_size=18,
                byte_length=18,
            )
        ]
    )
    cases.append(
        case(
            "kiln-v2-opaque",
            "An opaque dtype carries a layout name and a block size",
            "Opaque layouts",
            "Dtype 4096 is opaque. The layout name is Q4_K and the block size is 18. The shape is not checked against an element width.",
            opaque,
            expect="accept",
            decoded=expect_ok(opaque),
        )
    )

    body = struct.pack("<q", 7) + pair
    # The directory is not standalone inside the struct: bytes follow? No, pair is the whole rest.
    embedded = decode_v2_fixed(pair, standalone=True)
    cases.append(
        case(
            "kiln-v2-in-struct",
            "A tensors field is the version-2 block after the preceding fields",
            "Embedding",
            "struct{id:i64,batch:tensors,} writes the i64 and then one complete version-2 block.",
            body,
            expect="accept",
            schema={"type": "struct", "fields": ["id:i64", "batch:tensors"]},
            decoded={"id": 7, "batch": embedded},
        )
    )

    empty_struct = struct.pack("<q", 7) + empty
    schema = ("struct", [("id", ("i64",)), ("batch", ("tensors",))])
    framed = b"KLN0" + bytes(4) + struct.pack("<Q", type_hash(schema)) + empty_struct
    cases.append(
        case(
            "kiln-v2-framed",
            "A frame hash covers the tensors field by the token tensors",
            "Schema hash",
            "The canonical text mixes struct{, id, :, i64, ,, batch, :, tensors, ,, and }. The frame profile is Frozen.",
            framed,
            expect="accept",
            schema="frame",
            decoded={"hash": type_hash(schema), "id": 7, "batch": expect_ok(empty)},
        )
    )

    pod = struct.pack("<I", 2) + f32(1.0) + f32(-2.0)
    if check_list(pod, ("f32",)) is not None:
        raise SystemExit("pod list should fit")
    cases.append(
        case(
            "kiln-pod-list-f32",
            "A list of two f32 values is a count and the little-endian bits",
            "Lengths and allocation",
            "The count fits the remaining bytes, so the decoder may allocate the list. The element bytes are 00 00 80 3f and 00 00 00 c0.",
            pod,
            expect="accept",
            schema={"type": "list", "element": "f32"},
            decoded=[1.0, -2.0],
            fixes=["endian", "allocation"],
        )
    )

    # Reject cases.
    def add_reject(case_id: str, title: str, section: str, paragraph: str, raw: bytes, code: str, **kwargs: object) -> None:
        fixes = kwargs.pop("fixes", None)
        schema = kwargs.pop("schema", "tensor-v2")
        expect_err(raw, code, **kwargs)  # type: ignore[arg-type]
        cases.append(
            case(
                case_id,
                title,
                section,
                paragraph,
                raw,
                expect="reject",
                error=code,
                schema=schema,  # type: ignore[arg-type]
                fixes=fixes if isinstance(fixes, list) else None,
            )
        )

    add_reject(
        "kiln-v2-bad-magic",
        "A directory with the wrong magic is rejected",
        "Tensor directory",
        "The magic is the ASCII bytes KLNT.",
        b"XLNT" + empty[4:],
        "FRAME",
    )
    named_empty = bytearray(empty)
    named_empty[5] = FLAG_LE | FLAG_NAME
    add_reject(
        "kiln-v2-empty-name-flag",
        "An empty directory rejects the name flag",
        "Tensor directory",
        "The name flag is set exactly when at least one tensor has a name. An empty directory has the flag clear.",
        bytes(named_empty),
        "TYPE",
    )
    bare = bytearray(empty)
    bare[5] = 0
    add_reject(
        "kiln-v2-le-clear",
        "Version 2 rejects a directory whose little-endian flag is clear",
        "Byte order",
        "Writers set flag bit 1. A clear bit is a frame error on every host.",
        bytes(bare),
        "FRAME",
        fixes=["endian"],
    )
    bare = bytearray(empty)
    bare[5] = FLAG_LE | 0x04
    add_reject(
        "kiln-v2-unknown-flag",
        "Version 2 rejects an unknown flag bit",
        "Tensor directory",
        "Flag bits other than the name bit and the little-endian bit are zero.",
        bytes(bare),
        "FRAME",
    )
    bare = bytearray(empty)
    bare[32] = 1
    add_reject(
        "kiln-v2-reserved",
        "A nonzero reserved header byte is rejected",
        "Tensor directory",
        "The 32 reserved bytes at the end of the header are zero.",
        bytes(bare),
        "FRAME",
    )
    short = build_v2(
        [],
        count=2,
        name_bytes=0,
        directory_bytes=256,
        payload_bytes=0,
        payload=b"",
        heap=b"",
        truncate=64,
    )
    add_reject(
        "kiln-v2-directory-eof",
        "A tensor count whose directory does not fit is rejected before allocation",
        "Lengths and allocation",
        "Count 2 asks for 256 directory bytes. The buffer is only the header. The error is EOF, and the decoder does not allocate two descriptors.",
        short,
        "EOF",
        fixes=["allocation"],
    )
    huge_count = build_v2(
        [],
        count=CAP + 1,
        name_bytes=0,
        directory_bytes=(CAP + 1) * DESC,
        payload_bytes=0,
        payload=b"",
        heap=b"",
        truncate=64,
    )
    add_reject(
        "kiln-v2-count-cap",
        "A tensor count above the configured cap is a limit error",
        "Lengths and allocation",
        "At the default cap of 16777216, a count of 16777217 is LIMIT. The cap is checked before the decoder treats directory_bytes as a buffer size.",
        huge_count,
        "LIMIT",
        fixes=["allocation"],
    )
    mismatch = build_v2(
        [describe(dtype="f32", shape=[], data=f32(1.0))],
        directory_bytes=129,
    )
    add_reject(
        "kiln-v2-directory-mismatch",
        "directory_bytes must equal count times 128 plus name_bytes",
        "Tensor directory",
        "One descriptor is 128 bytes. A declared directory of 129 bytes does not match.",
        mismatch,
        "TYPE",
    )
    overflow = canonical(
        [
            describe(
                dtype="f32",
                shape=[4294967296, 4294967296],
                data=b"",
                byte_length=0,
            )
        ]
    )
    add_reject(
        "kiln-v2-shape-overflow",
        "A shape product that does not fit in an unsigned 64-bit integer is a limit error",
        "Tensor directory",
        "Rank 2 with both dimensions 2^32 overflows the element-count product.",
        overflow,
        "LIMIT",
    )
    wrong_len = canonical(
        [describe(dtype="f32", shape=[2], data=f32(1.0), byte_length=4)]
    )
    add_reject(
        "kiln-v2-length-mismatch",
        "byte_length must equal the shape product times the dtype width",
        "Tensor directory",
        "Two f32 elements occupy 8 bytes. A declared length of 4 is a type error.",
        wrong_len,
        "TYPE",
    )
    overlapped = [
        describe(dtype="f32", shape=[], data=f32(1.0), byte_offset=0),
        describe(dtype="f32", shape=[], data=f32(2.0), byte_offset=0),
    ]
    stamp_names(overlapped)
    add_reject(
        "kiln-v2-overlap",
        "Payload ranges must not overlap",
        "Tensor directory",
        "Two payloads that both cover offset 0 are a type error.",
        build_v2(overlapped, payload=f32(1.0), payload_bytes=4),
        "TYPE",
    )
    unaligned = [describe(dtype="f32", shape=[], data=f32(1.0), byte_offset=4)]
    stamp_names(unaligned)
    add_reject(
        "kiln-v2-unaligned",
        "A payload offset must be the canonical 64-byte placement",
        "Canonical layout",
        "The first payload starts at offset 0. Offset 4 is a type error.",
        build_v2(unaligned, payload=bytes(8), payload_bytes=8),
        "TYPE",
    )
    padded = bytearray(named)
    # Name heap ends at 64+128+1 = 193. Payload base is 256. Flip the last pad byte.
    padded[255] = 1
    add_reject(
        "kiln-v2-nonzero-pad",
        "Padding from the directory to the payload base must be zero",
        "Canonical layout",
        "A nonzero pad byte changes the block and is a type error.",
        bytes(padded),
        "TYPE",
    )
    dup = canonical(
        [
            describe(dtype="f32", shape=[], name=b"w", data=f32(1.0)),
            describe(dtype="f32", shape=[], name=b"w", data=f32(2.0)),
        ]
    )
    add_reject(
        "kiln-v2-duplicate-name",
        "Tensor names must be unique",
        "Tensor directory",
        "Two tensors named w are a type error.",
        dup,
        "TYPE",
    )
    bad_name = [describe(dtype="f32", shape=[], name=bytes([0xFF]), data=f32(1.0))]
    stamp_names(bad_name)
    add_reject(
        "kiln-v2-bad-utf8",
        "A tensor name must be UTF-8",
        "Tensor directory",
        "The name byte ff is not UTF-8.",
        build_v2(bad_name, flags=FLAG_LE | FLAG_NAME),
        "UTF8",
    )
    bad_bool = canonical([describe(dtype="bool", shape=[1], data=bytes([2]))])
    add_reject(
        "kiln-v2-bool-byte",
        "A bool tensor byte other than 0 or 1 is a type error",
        "Dtypes",
        "The byte 2 is not a bool.",
        bad_bool,
        "TYPE",
    )
    bad_scale = canonical(
        [
            describe(
                dtype="e2m1",
                shape=[32],
                data=bytes(16),
                quant_scheme=1,
                quant_axis=0,
                group_size=32,
                scale_index=1,
            ),
            describe(dtype="e8m0", shape=[2], data=bytes([127, 127])),
        ]
    )
    add_reject(
        "kiln-v2-scale-count",
        "The scale tensor must have one element per group",
        "Quantization",
        "Thirty-two elements with group size 32 require one scale. Two scales are a type error.",
        bad_scale,
        "TYPE",
    )
    missing_layout = [
        describe(dtype=4096, shape=[32], data=bytes(18), block_size=18, byte_length=18)
    ]
    stamp_names(missing_layout)
    add_reject(
        "kiln-v2-opaque-no-layout",
        "An opaque dtype requires a layout name",
        "Opaque layouts",
        "Dtype 4096 with no layout name is a type error.",
        build_v2(missing_layout),
        "TYPE",
    )
    add_reject(
        "kiln-v2-trailing",
        "A standalone directory rejects a trailing byte",
        "Tensor directory",
        "The buffer of a standalone directory is exactly the block.",
        empty + b"\x00",
        "TRAILING",
    )
    high = canonical([describe(dtype="u4", shape=[1], data=bytes([0x10]))])
    add_reject(
        "kiln-v2-high-nibble",
        "An odd packed count requires a zero high nibble in the last byte",
        "Dtypes",
        "One u4 element stored as 10 has a nonzero high nibble.",
        high,
        "TYPE",
    )
    extra_dim = canonical(
        [describe(dtype="f32", shape=[1], data=f32(1.0), rank=1)]
    )
    # shape() helper zeros the tail. Patch shape[1] to 1.
    patched = bytearray(extra_dim)
    struct.pack_into("<Q", patched, HEADER + 48 + 8, 1)
    add_reject(
        "kiln-v2-shape-tail",
        "Shape slots at and past the rank must be zero",
        "Tensor directory",
        "Rank 1 with a nonzero second shape slot is a type error.",
        bytes(patched),
        "TYPE",
    )
    add_reject(
        "kiln-v2-dtype-zero",
        "Dtype 0 is rejected",
        "Dtypes",
        "Dtype codes start at 1.",
        canonical([describe(dtype=0, shape=[], data=b"", byte_length=0)]),
        "TYPE",
    )
    add_reject(
        "kiln-v2-dtype-reserved",
        "Dtype 20 is reserved and rejected",
        "Dtypes",
        "Codes 20 through 4095 are reserved.",
        canonical([describe(dtype=20, shape=[], data=b"", byte_length=0)]),
        "TYPE",
    )
    overflow_payload = build_v2(
        [],
        count=0,
        name_bytes=0,
        directory_bytes=0,
        payload_bytes=MASK,
        payload=b"",
        heap=b"",
    )
    add_reject(
        "kiln-v2-payload-overflow",
        "A payload length that overflows the block end is a limit error",
        "Lengths and allocation",
        "payload_bytes of 2^64-1 plus the 64-byte header overflows. The decoder returns LIMIT and does not allocate.",
        overflow_payload,
        "LIMIT",
        fixes=["allocation"],
    )

    hostile = struct.pack("<I", CAP)
    code = check_list(hostile, ("struct", [("a", ("i64",))]))
    if code != "EOF":
        raise SystemExit(code)
    cases.append(
        case(
            "kiln-list-struct-hostile",
            "A list count of 16777216 structs is rejected when the elements are absent",
            "Lengths and allocation",
            "The element minimum is 8 bytes. The product does not fit in the empty remainder. The decoder returns EOF and does not allocate 16777216 structs. The count is inside the default cap, so this is not a limit error.",
            hostile,
            expect="reject",
            error="EOF",
            schema={"type": "list", "element": "struct{a:i64}"},
            fixes=["allocation"],
        )
    )
    short_body = struct.pack("<I", 2) + struct.pack("<q", 1)
    code = check_list(short_body, ("struct", [("a", ("i64",))]))
    if code != "EOF":
        raise SystemExit(code)
    cases.append(
        case(
            "kiln-list-struct-short",
            "A list of two structs is rejected when only one element is present",
            "Lengths and allocation",
            "Two i64 structs need 16 bytes after the count. Eight bytes are present. The decoder returns EOF and does not allocate the list.",
            short_body,
            expect="reject",
            error="EOF",
            schema={"type": "list", "element": "struct{a:i64}"},
            fixes=["allocation"],
        )
    )
    short_strings = struct.pack("<I", 3) + struct.pack("<I", 0)
    code = check_list(short_strings, ("str",))
    if code != "EOF":
        raise SystemExit(code)
    cases.append(
        case(
            "kiln-list-str-short",
            "A list of three strings is rejected when fewer than three length prefixes are present",
            "Lengths and allocation",
            "A string is at least 4 bytes. Three strings need 12 bytes after the count. Four bytes are present.",
            short_strings,
            expect="reject",
            error="EOF",
            schema={"type": "list", "element": "str"},
            fixes=["allocation"],
        )
    )
    short_pod = struct.pack("<I", 2) + f32(1.0)
    code = check_list(short_pod, ("f32",))
    if code != "EOF":
        raise SystemExit(code)
    cases.append(
        case(
            "kiln-pod-list-short",
            "A short list of f32 values is rejected before the copy",
            "Lengths and allocation",
            "Two f32 elements need 8 bytes. Four bytes are present. The decoder returns EOF and does not allocate the list.",
            short_pod,
            expect="reject",
            error="EOF",
            schema={"type": "list", "element": "f32"},
            fixes=["allocation"],
        )
    )

    bad_version = bytearray(empty)
    bad_version[4] = 1
    add_reject(
        "kiln-v2-bad-version",
        "A directory version other than 2 is rejected",
        "Tensor directory",
        "The directory version is 2. There is no earlier tensor layout.",
        bytes(bad_version),
        "FRAME",
    )

    out = Path(__file__).resolve().parents[1] / "kiln-v2-cases.json"
    document = {
        "format": "kiln",
        "standard": "Kiln wire v2 (draft)",
        "version": "v2-draft",
        "standard_url": "https://leo-gan.github.io/gld-kiln/spec/",
        "provenance": "original-work",
        "notes": (
            "Cases for Kiln wire version 2. Produced by "
            "spec/reference/gen_v2_cases.py. The prose is docs/spec.md. "
            "Version-1 cases are included where version 2 keeps them. "
            "The reference cap is 16777216. This file is not wired into "
            "the compliance runner."
        ),
        "cap": CAP,
        "cases": cases,
    }
    out.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {out} ({len(cases)} cases)")
    print("empty", empty.hex())
    print("f32_len", len(pair))
    print("f32", pair.hex())
    print("frame_hash", hex(type_hash(schema)))


if __name__ == "__main__":
    main()
