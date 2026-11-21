"""Test-decode v4's payload with v4's own deserializer block in wasmoon, using v4's evaluated env table.
This proves the harness before adapting it to v5."""
import json
import re
import subprocess
import sys

v4 = open('Samples/PSU/v4/1.lua', encoding='utf-8', errors='replace').read()

tail_idx = v4.rfind(',...);')
print("v4 ',...);' at:", tail_idx)

def find_table_end(s, start):
    """scan backwards from start for the matching '{' of the last '}' before start"""

    j = start - 1
    while j >= 0 and s[j] in ' \r\n':
        j -= 1
    assert s[j] == '}', f"expected '}}' at {j}, got {s[j]!r}"
    depth = 0
    i = j
    while i >= 0:
        c = s[i]
        if c == '}':
            depth += 1
        elif c == '{':
            depth -= 1
            if depth == 0:
                return i
        i -= 1
    return -1

tbl_open = find_table_end(v4, tail_idx)

pre = tbl_open
if v4[pre - 1] == '(':
    tbl_expr_start = pre - 1
else:
    tbl_expr_start = pre
tbl_src = v4[tbl_open:tail_idx]
print("v4 env table src len:", len(tbl_src))
open('Samples/PSU/v5/_v4_envtable1.lua', 'w', encoding='utf-8').write('return ' + tbl_src)

print("saved v4 env table")
