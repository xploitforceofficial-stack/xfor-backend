"""Extract v4 env table: handles '}),...);' closing pattern."""
v4 = open('Samples/PSU/v4/1.lua', encoding='utf-8', errors='replace').read()

tail_idx = v4.rfind(',...);')
print("v4 ',...);' at:", tail_idx)
print("tail context:", repr(v4[tail_idx - 80:tail_idx + 20]))

j = tail_idx - 1
while j >= 0 and v4[j] in ' \r\n':
    j -= 1
assert v4[j] == ')', f"expected ')' got {v4[j]!r}"
j -= 1
while j >= 0 and v4[j] in ' \r\n':
    j -= 1
assert v4[j] == '}', f"expected '}}' got {v4[j]!r}"

close_pos = j
depth = 0
i = close_pos
while i >= 0:
    c = v4[i]
    if c == '}':
        depth += 1
    elif c == '{':
        depth -= 1
        if depth == 0:
            break
    i -= 1
tbl_open = i
tbl_src = v4[tbl_open:close_pos + 1]
print("v4 env table src len:", len(tbl_src))
open('Samples/PSU/v5/_v4_envtable1.lua', 'w', encoding='utf-8').write('return ' + tbl_src)
print("saved. head:", repr(tbl_src[:100]))
print("tail:", repr(tbl_src[-100:]))
