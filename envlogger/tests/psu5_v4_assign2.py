"""Find the outer assignment: the LZW IIFE result. Search back for 'local X=([function]' pattern."""
import re

v4 = open('Samples/PSU/v4/1.lua', encoding='utf-8', errors='replace').read()
i = v4.find('"PSU|')

head = v4[:i]
stmts = [(m.start(), m.group(1)) for m in re.finditer(r'local\s+([a-zA-Z][\w,]*)\s*=\s*\(', head)]
print("local X=( statements in head (last 6):")
for st, nm in stmts[-6:]:
    print(f"  @{st}: local {nm}=(")

call_end = v4.find(')', i)
anchor = v4.find(',(#R-G);', i)

for st, nm in stmts[-4:]:
    depth = 0
    j = st + len(f'local {nm}=')
    inside_str = False
    BS = chr(92)
    k = j
    while k < len(v4):
        c = v4[k]
        if inside_str:
            if c == BS:
                k += 2
                continue
            if c == '"':
                inside_str = False
            k += 1
            continue
        if c == '"':
            inside_str = True
            k += 1
            continue
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                break
        k += 1
    print(f"local {nm}=( closes at {k} (anchor at {anchor})  match={abs(k - anchor) < 12}")
    if abs(k - anchor) < 12:
        print("  >>> candidate:", v4[st:st + 80])
