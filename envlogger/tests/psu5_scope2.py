"""Find the immediate enclosing function header of 'return A(I(),{},v())(...)': scan all
'function ... (.*)' headers, compute each function's body extent via keyword counting
(function..end nesting), and find the innermost one containing the call."""
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

toks = []
k = 0
n = len(vmbody)
while k < n:
    if vmbody[k] in '"\'':
        q = vmbody[k]
        k += 1
        while k < n:
            if vmbody[k] == '\\':
                k += 2
                continue
            if vmbody[k] == q:
                k += 1
                break
            k += 1
        toks.append((k, 'STR'))
        continue
    m = re.match(r'function\b', vmbody[k:])
    if m:
        toks.append((k, 'function'))
        k += 8
        continue
    m = re.match(r'end\b', vmbody[k:])
    if m:
        toks.append((k, 'end'))
        k += 3
        continue
    m = re.match(r'if\b', vmbody[k:])
    if m:
        toks.append((k, 'if'))
        k += 2
        continue
    m = re.match(r'do\b', vmbody[k:])
    if m:
        toks.append((k, 'do'))
        k += 2
        continue
    k += 1

funcs = [(pos, 'function') for pos, t in toks if t == 'function']
funcs.sort(reverse=True)
for st, _ in funcs:
    if st >= callpos:
        continue

    depth = 0
    k = st
    while k < n:
        c = vmbody[k]
        if c in '"\'':
            q = c
            k += 1
            while k < n:
                if vmbody[k] == '\\':
                    k += 2
                    continue
                if vmbody[k] == q:
                    k += 1
                    break
                k += 1
            continue
        m1 = re.match(r'function\b', vmbody[k:])
        if m1:
            depth += 1
            k += 8
            continue
        m2 = re.match(r'end\b', vmbody[k:])
        if m2:
            depth -= 1
            if depth == 0:
                endpos = k
                break
            k += 3
            continue
        k += 1
    else:
        continue
    if endpos >= callpos:

        hdr = vmbody[st:st+120]
        print(f"innermost enclosing function @ {st}: {hdr!r}")
        print("body extent:", st, "..", endpos, " call at", callpos)
        break
