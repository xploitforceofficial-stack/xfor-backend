"""Show v4 skeleton middle: payload position, deserializer call chain, dispatcher."""
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

big = [(m.start(), len(m.group())) for m in re.finditer(r'S{200,}', v4s)]
print("huge string runs in v4 skeleton:", [(p, l) for p, l in big][:5])

for m in list(re.finditer(r'while', v4s))[:6]:
    print("\nwhile @", m.start(), ":", v4s[m.start():m.start()+150])

print("\nreturn(function occurrences:", [m.start() for m in re.finditer(r'return\(function', v4s)][:8])

tail = v4s[-1600:-900]
print("\nv4 tail pre-envtable:", tail)
