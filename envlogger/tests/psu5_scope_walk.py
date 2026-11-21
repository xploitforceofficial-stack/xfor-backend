"""Walk enclosing scopes of the final call to identify which A/I/v are in scope."""
import re

s = open('Samples/PSU/v5/1.lua', encoding='utf-8', errors='replace').read()
body_src = s[1000524:]

def strip_keep_space(src):
    out = []
    i = 0
    n = len(src)
    BS = chr(92)
    while i < n:
        c = src[i]
        if c == '"' or c == "'":
            q = c
            j = i + 1
            while j < n:
                if src[j] == BS:
                    j += 2
                    continue
                if src[j] == q:
                    j += 1
                    break
                j += 1
            out.append('Q')
            i = j
        elif src[i:i+2] == '--':
            j = i + 2
            if j < n and src[j] == '[':
                eq = 0
                k = j + 1
                while k < n and src[k] == '=':
                    eq += 1
                    k += 1
                if k < n and src[k] == '[':
                    close = ']' + '=' * eq + ']'
                    f = src.find(close, k + 1)
                    i = (f + len(close)) if f != -1 else n
                    continue
            while j < n and src[j] != '\n':
                j += 1
            i = j
        else:
            out.append(c)
            i += 1
    return ''.join(out)

clean = strip_keep_space(body_src)
vmbody = clean[:clean.find('end)(({')]

callpos = vmbody.find('return A(I(),{},v())(...);')

defs = []
for m in re.finditer(r'local function (\w+)\s*\(', vmbody[:callpos]):
    defs.append((m.start(), m.group(1)))
for m in re.finditer(r'local (\w+)\s*=\s*function\s*\(', vmbody[:callpos]):
    defs.append((m.start(), m.group(1)))
print("local function defs before call:")
for pos, nm in defs:
    print(f"  @{pos}: {nm}")

enc = None
depth = 0

for m in re.finditer(r'function\s*\(([^)]*)\)', vmbody[:callpos]):

    st = m.start()
    k = m.end()
    fdepth = 1
    in_str = False
    while k < len(vmbody):
        c = vmbody[k]
        if not in_str and vmbody[k:k+8] == 'function':
            fdepth += 1
            k += 8
            continue
        if not in_str and vmbody[k:k+3] == 'end':
            fdepth -= 1
            if fdepth == 0:
                break
            k += 3
            continue
        if c in '"\'':
            in_str = not in_str
        k += 1
    else:
        continue
    if k >= callpos and st <= callpos:
        enc = (st, m.group(1))
print("\nimmediate enclosing function of the call:", enc)
