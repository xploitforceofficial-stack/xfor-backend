"""Find the LZW IIFE binding: scan balance from 'local u,t=(function(o)...' to the call end."""
v4 = open('Samples/PSU/v4/1.lua', encoding='utf-8', errors='replace').read()

st = v4.find('local u,t=(')
print("found at:", st, repr(v4[st:st + 90]))

BS = chr(92)
i = st + len('local u,t=')
depth = 0
in_str = False
while i < len(v4):
    c = v4[i]
    if in_str:
        if c == BS:
            i += 2
            continue
        if c == '"':
            in_str = False
        i += 1
        continue
    if c == '"':
        in_str = True
        i += 1
        continue
    if c == '(':
        depth += 1
    elif c == ')':
        depth -= 1
        if depth == 0:
            break
    i += 1
print("balance closes at:", i)
print("context at close:", repr(v4[i:i + 60]))
print("context before close:", repr(v4[i - 40:i + 10]))
