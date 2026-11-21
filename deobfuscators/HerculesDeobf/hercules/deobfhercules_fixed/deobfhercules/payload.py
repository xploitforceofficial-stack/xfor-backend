from __future__ import annotations
import re
import sys
from typing import Tuple, Optional

sys.set_int_max_str_digits(2_000_000)

_ANCHOR_RE = re.compile(r"_ENV\s*\)\s*\(\s*\)")

_PAYLOAD_RE = re.compile(
    r"(\w+)"
    r"\("
    r"(\w+)"
    r"\("
    r"'([^']*)'"
    r","
    r"'([^']*)'"
    r"\)"
    r","
    r"\(\s*getfenv\s+and\s+getfenv\s*\(\s*0\s*\)\s*\)"
    r"\s*or\s*"
    r"_ENV"
    r"\s*\)"
    r"\s*\(\s*\)"
)

_MAX_PAYLOAD_WINDOW = 256 * 1024 * 1024

def _decode_backslash_string(s: str) -> bytes:

    out = bytearray()
    i = 0
    n = len(s)
    while i < n:
        ch = s[i]
        if ch == "\\" and i + 1 < n:
            j = i + 1
            num = ""
            while j < n and s[j].isdigit():
                num += s[j]
                j += 1
            if num:
                out.append(int(num) & 0xFF)
                i = j
                continue
        out.append(ord(ch) & 0xFF)
        i += 1
    return bytes(out)

def find_payload(src: str) -> Optional[Tuple[str, str, str, str, int]]:

    if "_ENV" not in src:
        return None
    if "getfenv" not in src:
        return None
    if "'" not in src:
        return None

    anchor = _ANCHOR_RE.search(src)
    if anchor is None:
        return None
    anchor_end = anchor.end()

    window_start = max(0, anchor_end - _MAX_PAYLOAD_WINDOW)
    window = src[window_start:anchor_end]

    m = _PAYLOAD_RE.search(window)
    if m is None:
        return None

    abs_pos = window_start + m.start()
    return (m.group(1), m.group(2), m.group(3), m.group(4), abs_pos)

def decode_payload(encoded_str: str, charset_str: str) -> bytes:

    charset_bytes = _decode_backslash_string(charset_str)
    if not charset_bytes:
        raise ValueError("Empty charset")
    base = len(charset_bytes)
    decode_lookup = {chr(charset_bytes[i]): i for i in range(base)}

    inner = _decode_backslash_string(encoded_str).decode("latin-1")

    raw = bytearray()
    for chunk in inner.split("_"):
        if not chunk:
            continue
        n = 0
        for ch in chunk:
            v = decode_lookup.get(ch)
            if v is None:
                raise ValueError(f"Character {ch!r} not in charset")
            n = n * base + v
        if n < 0 or n > 0xFF:
            raise ValueError(f"Decoded value {n} out of byte range")
        raw.append(n)

    data = bytes(raw[0::2])
    return data

def is_hercules(src: str) -> bool:

    head = src[:2048]
    if "Hercules" in head and "Obfuscated by" in head:
        return True

    if find_payload(src) is not None:
        return True

    if find_bytecode_encoder_payload(src) is not None:
        return True
    return False

import re as _re

_BYTECODE_ENCODER_RE = _re.compile(
    r'local\s+e\s*,\s*o\s*,\s*d\s*=\s*"'
    r'([0-9A-Fa-f]+)'
    r'"\s*,\s*'
    r'(\d+)'
    r'\s*,\s*\{\s*\}'
)

def find_bytecode_encoder_payload(src: str) -> Optional[Tuple[str, int, int]]:

    if "tonumber(e:sub" not in src:
        return None
    m = _BYTECODE_ENCODER_RE.search(src)
    if m is None:
        return None
    return (m.group(1), int(m.group(2)), m.start())

def decode_bytecode_encoder(hex_str: str, offset: int) -> bytes:

    if len(hex_str) % 2 != 0:
        raise ValueError("Hex string has odd length")
    raw = bytearray()
    for i in range(0, len(hex_str), 2):
        b = int(hex_str[i:i+2], 16)
        raw.append((b - offset) % 256)
    return bytes(raw)
