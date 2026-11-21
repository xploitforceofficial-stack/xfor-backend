"""Token-level scan of the PSU v5 file head to establish the real top-level structure."""
s = open('Samples/PSU/v5/1.lua', encoding='utf-8', errors='replace').read()
BS = chr(92)

print("=== raw head (first 400 chars):")
print(repr(s[:400]))
print()

i = 0
n = len(s)
depth = 0
events = []

def skip_string(j):
    q = s[j]
    j += 1
    while j < n:
        if s[j] == BS:
            j += 2
            continue
        if s[j] == q:
            return j + 1
        j += 1
    return n

def skip_long(j):
    eq = 0
    k = j + 1
    while k < n and s[k] == '=':
        eq += 1
        k += 1
    if k < n and s[k] == '[':
        close = ']' + '=' * eq + ']'
        f = s.find(close, k + 1)
        return (f + len(close)) if f != -1 else n
    return j + 1

while i < n:
    c = s[i]
    if c == '"' or c == "'":
        i = skip_string(i)
        continue
    if s[i:i + 2] == '--':
        j = i + 2
        if j < n and s[j] == '[':
            i = skip_long(j)
        else:
            while i < n and s[i] != '\n':
                i += 1
        continue
    if c == '[' and i + 1 < n and s[i + 1] in '=[':

        eq = 0
        k = i + 1
        while k < n and s[k] == '=':
            eq += 1
            k += 1
        if k < n and s[k] == '[':
            i = skip_long(i)
            continue
    if c in '({[':
        events.append((i, depth, c))
        depth += 1
    elif c in ')}]':
        depth -= 1
        events.append((i, depth, c))
    i += 1

print("=== first 60 bracket events (pos, depth_after, char):")
for e in events[:60]:
    pos, d, ch = e
    snippet = s[max(0, pos - 25):pos + 25].replace('\n', ' ')
    print(f"  {pos:8d} d={d} {ch}  ...{snippet!r}...")
print()
print("total open/close events:", len(events))
print("min depth reached:", min((e[1] for e in events), default=0))
