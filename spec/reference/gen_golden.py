"""Write golden Kiln bytes from the Python reference decoder."""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

from kiln_ref import MESSAGE, POINT, encode, encode_framed


def main() -> None:
    root = Path(__file__).resolve().parents[2]
    out = root / "spec" / "golden"
    out.mkdir(parents=True, exist_ok=True)
    message = {
        "f_bool": True,
        "f_int32": -2,
        "f_int64": 99,
        "f_float64": 1.5,
        "f_string": "hi",
        "f_bool_2": False,
        "f_int32_2": 7,
        "f_string_2": "z",
    }
    (out / "message.kiln").write_bytes(encode(MESSAGE, message))
    (out / "message.frame.kiln").write_bytes(encode_framed(MESSAGE, message))
    (out / "point.kiln").write_bytes(encode(POINT, {"x": 9, "y": -4}))
    print("wrote", out)


if __name__ == "__main__":
    main()
