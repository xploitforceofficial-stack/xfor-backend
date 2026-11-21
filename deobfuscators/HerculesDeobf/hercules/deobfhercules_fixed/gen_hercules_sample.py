from __future__ import annotations
import argparse
import random
import struct
import sys
from pathlib import Path

class BytecodeBuffer:
    def __init__(self):
        self.buf = bytearray()

    def add_byte(self, v: int) -> None:

        self.buf.append(v & 0xFF)
        self.buf.append(ord("\\"))

    def write_u8(self, v: int) -> None:
        self.add_byte(v & 0xFF)

    def write_u16(self, v: int) -> None:
        for i in range(2):
            self.write_u8((v >> (i * 8)) & 0xFF)

    def write_u32(self, v: int) -> None:
        for i in range(4):
            self.write_u8((v >> (i * 8)) & 0xFF)

    def write_f64(self, value: float) -> None:

        if value == 0.0:
            sign = 0
            if str(value) == "-0.0":
                sign = 1
            exponent, mantissa = 0, 0
        elif value != value:
            exponent, mantissa = 2047, 1
        elif value == float("inf"):
            exponent, mantissa = 2047, 0
            sign = 0
        elif value == float("-inf"):
            exponent, mantissa = 2047, 0
            sign = 1
        else:
            sign = 1 if value < 0 else 0
            v = abs(value)
            m, e = math_frexp(v)
            mantissa = int((m * 2 - 1) * (2 ** 52))
            exponent = e + 1022
        high = sign * (2 ** 31) + exponent * (2 ** 20) + (mantissa // (2 ** 32))
        low = mantissa % (2 ** 32)
        self.write_u32(low)
        self.write_u32(high)

    def write_string(self, s: str) -> None:
        self.write_u32(len(s))
        for ch in s:
            self.write_u8(ord(ch))

    def write_chunk(
        self,
        upvals: int,
        params: int,
        max_stack: int,
        instructions: list,
        constants: list,
        protos: list,
    ) -> None:
        self.write_u8(upvals)
        self.write_u8(params)
        self.write_u8(max_stack)
        self.write_u32(len(instructions))
        for inst in instructions:
            self.write_u32(inst["value"])
            self.write_u8(inst["enum"])
            type_str = inst["type"]
            type_id = {"ABC": 1, "ABx": 2, "AsBx": 3}[type_str]
            self.write_u8(type_id)
            self.write_u16(inst["A"])

            self.write_u8(1 if inst["mode"]["b"] == "OpArgK" else 0)

            self.write_u8(1 if inst["mode"]["c"] == "OpArgK" else 0)
            if type_str == "ABC":
                self.write_u16(inst["B"])
                self.write_u16(inst["C"])
            elif type_str == "ABx":
                self.write_u32(inst["Bx"])
            elif type_str == "AsBx":
                self.write_u32(inst["sBx"] + 131071)
        self.write_u32(len(constants))
        for c in constants:
            if isinstance(c, bool):
                self.write_u8(1)
                self.write_u8(1 if c else 0)
            elif isinstance(c, (int, float)):
                self.write_u8(3)
                self.write_f64(float(c))
            elif isinstance(c, str):
                self.write_u8(4)
                self.write_string(c)
            else:
                raise TypeError(f"Unsupported constant type: {type(c)}")
        self.write_u32(len(protos))
        for p in protos:
            self.write_chunk(**p)

def math_frexp(v: float):

    if v == 0.0:
        return 0.0, 0
    import math
    return math.frexp(v)

def encode_string_as_basen(bytecode: bytes, charset: str) -> str:

    base = len(charset)
    out = []
    for b in bytecode:
        n = b
        digits = []
        if n == 0:
            digits.append(charset[0])
        else:
            while n > 0:
                r = n % base
                digits.append(charset[r])
                n //= base
            digits.reverse()
        out.append("".join(digits))
    return "_".join(out)

def encode_to_backslash_str(s: str) -> str:

    return "".join(f"\\{ord(ch)}" for ch in s)

def encode_payload(bytecode: bytes, charset: str) -> str:

    inner = encode_string_as_basen(bytecode, charset)
    return encode_to_backslash_str(inner)

def encode_charset(charset: str) -> str:

    return encode_to_backslash_str(charset)

def build_test_chunk():

    instructions = [

        {
            "value": 0, "enum": 5, "type": "ABx",
            "A": 0, "Bx": 0,
            "mode": {"b": "OpArgK", "c": "OpArgN"},
        },

        {
            "value": 0, "enum": 1, "type": "ABx",
            "A": 1, "Bx": 1,
            "mode": {"b": "OpArgK", "c": "OpArgN"},
        },

        {
            "value": 0, "enum": 28, "type": "ABC",
            "A": 0, "B": 2, "C": 1,
            "mode": {"b": "OpArgR", "c": "OpArgU"},
        },

        {
            "value": 0, "enum": 30, "type": "ABC",
            "A": 0, "B": 1, "C": 0,
            "mode": {"b": "OpArgU", "c": "OpArgN"},
        },
    ]
    constants = ["print", "Hello from Hercules!"]
    return {
        "upvals": 0,
        "params": 0,
        "max_stack": 3,
        "instructions": instructions,
        "constants": constants,
        "protos": [],
    }

def main():
    parser = argparse.ArgumentParser(description="Generate a Hercules 2.0.1 test sample.")
    parser.add_argument("output", help="Output .lua file path")
    parser.add_argument(
        "--variant",
        choices=["2.0.0", "2.0.1"],
        default="2.0.1",
        help="Hercules version format to emulate (default: 2.0.1)",
    )
    parser.add_argument("--seed", type=int, default=None, help="Random seed")
    parser.add_argument(
        "--watermark",
        choices=["v2.0.0", "v2.0.1", "none"],
        default="v2.0.0",
        help="Watermark comment to emit (manifest default is v2.0.0 text in both)",
    )
    args = parser.parse_args()

    if args.seed is not None:
        random.seed(args.seed)

    buf = BytecodeBuffer()
    chunk = build_test_chunk()
    buf.write_chunk(**chunk)
    raw_bytecode = bytes(buf.buf)

    chars = [chr(i) for i in range(1, 95)]
    random.shuffle(chars)
    charset = "".join(chars)

    encoded_bytecode = encode_payload(raw_bytecode, charset)
    encoded_charset = encode_charset(charset)

    if args.variant == "2.0.1":
        wrapper = (
            f"WrapState(BcToState('{encoded_bytecode}','{encoded_charset}'),"
            f"(getfenv and getfenv(0)) or _ENV)()"
        )
    else:
        wrapper = (
            f"WrapState(BcToState('{encoded_bytecode}','{encoded_charset}'),"
            f"(getfenv and getfenv(0))or _ENV)()"
        )

    parts = []
    if args.watermark == "v2.0.0":
        parts.append(
            "--[Obfuscated by Hercules v2.0.0 | hercules-obfuscator.xyz/discord | "
            "hercules-obfuscator.xyz/source]\n"
        )
    elif args.watermark == "v2.0.1":
        parts.append(
            "--[Obfuscated by Hercules v2.0.1 | hercules-obfuscator.xyz/discord | "
            "hercules-obfuscator.xyz/source]\n"
        )

    parts.append("-- Lua 5.3+ / Luau compatibility polyfills\n")
    parts.append("local function BcToState(...) return ... end\n")
    parts.append("local function WrapState(...) return ... end\n")
    parts.append("\n")
    parts.append(wrapper)
    parts.append("\n")

    output = "".join(parts)
    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(output, encoding="utf-8")
    print(f"Wrote {len(output)} bytes to {out_path}")
    print(f"  variant:  {args.variant}")
    print(f"  charset:  {len(charset)} chars (base-{len(charset)})")
    print(f"  bytecode: {len(raw_bytecode)} raw bytes")
    print(f"  encoded:  {len(encoded_bytecode)} chars")
    print(f"  watermark: {args.watermark}")

if __name__ == "__main__":
    main()
