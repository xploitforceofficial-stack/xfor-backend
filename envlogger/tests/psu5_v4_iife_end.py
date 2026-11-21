"""Continue the balance scan THROUGH the payload string to find the IIFE call close."""
v4 = open('Samples/PSU/v4/1.lua', encoding='utf-8', errors='replace').read()

BS = chr(92)

i = 4063 + len('local u,t=')
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
    if c == "'" and False:
        pass
    if c == '(':
        depth += 1
    elif c == ')':
        depth -= 1
        if depth == 0:
            break
    i += 1
print("IIFE ( ...) closes at:", i)
print("context after close:", repr(v4[i:i + 80]))
