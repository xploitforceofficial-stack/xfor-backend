"""Map v4's complete top-level structure to guide v5 reconstruction."""
import re

v4 = open('Samples/PSU/v4/1.lua', encoding='utf-8', errors='replace').read()
v5 = open('Samples/PSU/v5/_vmcode.lua', encoding='utf-8', errors='replace').read()

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

v4s = skeleton(v4)
v5s = skeleton(v5)
print("v4 skeleton len:", len(v4s))
print("v5 skeleton len:", len(v5s))
print()
print("=== v4 skeleton head (900):")
print(v4s[:900])
print()
print("=== v4 skeleton tail (900):")
print(v4s[-900:])
