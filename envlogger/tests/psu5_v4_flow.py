"""Extract v4 skeleton at the payload site and the main VM call to map execution flow."""
import re

def skeleton(src):
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
            out.append('S')
            i = j
        elif src[i:i + 2] == '--':
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
        elif c == '[':
            eq = 0
            j = i + 1
            while j < n and src[j] == '=':
                eq += 1
                j += 1
            if j < n and src[j] == '[':
                close = ']' + '=' * eq + ']'
                f = src.find(close, j + 1)
                out.append('S')
                i = (f + len(close)) if f != -1 else n
                continue
            out.append(c)
            i += 1
        elif c in ' \t\r\n':
            out.append(' ' if c == '\n' else '')
            i += 1
        else:
            out.append(c)
            i += 1
    return ''.join(out)

v4 = open('Samples/PSU/v4/1.lua', encoding='utf-8', errors='replace').read()
v4s = skeleton(v4)

m = re.search(r'[0-9a-z]{3000,}', v4)
print("v4 payload blob in original:", (m.start(), m.end()) if m else None, "len:", m.end()-m.start() if m else 0)

st = m.start()
print("\n=== v4 original around payload start:")
print(repr(v4[st-260:st+80]))
print("\n=== v4 original around payload end:")
en = m.end()
print(repr(v4[en-80:en+300]))
