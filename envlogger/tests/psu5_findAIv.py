"""Find A, I, v definitions in the vmbody: 'local function A', 'local I=', 'local v=' etc."""
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
        else:
            out.append(c)
            i += 1
    return ''.join(out)

clean = strip_keep_space(body_src)
j = clean.find('end)(({')
vmbody = clean[:j]

for name in ['A', 'I', 'v']:
    print(f"=== '{name}' occurrences:")
    pats = [
        (rf'local function {name}\(', 'local function'),
        (rf'local {name}\s*=', 'local assignment'),
        (rf'\b{name}\s*=\s*function', 'function assignment'),
    ]
    for pat, label in pats:
        for m in re.finditer(pat, vmbody):
            print(f"  {label} @{m.start()}: {vmbody[m.start():m.start()+100]!r}")
    uses = re.findall(rf'.{{40}}\b{name}\b.{{40}}', vmbody)
    print(f"  total bare uses: {len(uses)}")
    for u in uses[:4]:
        print("    ", u)
    print()
