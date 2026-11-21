"""Print enclosing function candidates of the final call (flush-safe version)."""
import re
import sys

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
print("callpos:", callpos, "vmbody len:", len(vmbody))
sys.stdout.flush()

stack = []
k = 0
n = len(vmbody)
in_str = False
while k < n:
    c = vmbody[k]
    if in_str:
        if c == '\\':
            k += 2
            continue
        if c in '"\'':
            in_str = False
        k += 1
        continue
    if c in '"\'':
        in_str = True
        k += 1
        continue
    if vmbody[k:k+8] == 'function':
        stack.append(k)
        k += 8
        continue
    if vmbody[k:k+3] == 'end' and stack:
        st = stack.pop()
        if st <= callpos <= k:
            print(f"ENCLOSING function @ {st}: {vmbody[st:st+130]!r}")
        k += 3
        continue
    k += 1

print("scan done. stack left:", len(stack))
