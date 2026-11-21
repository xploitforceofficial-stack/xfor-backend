"""Locate v4's payload representation: could be concatenated chunks, escape sequences, or byte() calls."""
import re
from collections import Counter

v4 = open('Samples/PSU/v4/1.lua', encoding='utf-8', errors='replace').read()
print("v4 file len:", len(v4))

print("string.char count:", len(re.findall(r'string%.char', v4)))
print("\\\\xNN escape count:", len(re.findall(r'\\\\x[0-9a-fA-F]{2}', v4)))
print("\\\\NNN dec escape count:", len(re.findall(r'\\\\[0-9]{2,3}', v4)))
print("\\\\u{...} escape count:", len(re.findall(r'\\\\u\{', v4)))

strs = re.findall(r"'([^'\\\\]{80,})'", v4)
print("long '...' strings:", len(strs))
if strs:
    for st in strs[:3]:
        print("  len", len(st), repr(st[:70]))
strs2 = re.findall(r'"([^"\\\\]{80,})"', v4)
print('long "..." strings:', len(strs2))
if strs2:
    for st in strs2[:3]:
        print("  len", len(st), repr(st[:70]))

print("gsub count:", len(re.findall(r'gsub', v4)))
print("table.concat count:", len(re.findall(r'table%.concat', v4)))
