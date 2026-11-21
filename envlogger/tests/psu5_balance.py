"""Balance analysis of rebuilt v5 body: find unbalanced parens."""
import re

src = open('Samples/PSU/v5/_rebuilt_body.lua', encoding='utf-8').read()

depth = 0
min_depth = 0
min_pos = 0
events = []
for i, c in enumerate(src):
    if c == '(':
        depth += 1
    elif c == ')':
        depth -= 1
        if depth < min_depth:
            min_depth = depth
            min_pos = i
    events.append(depth) if False else None

print("final paren depth:", depth)
print("min depth:", min_depth, "at pos", min_pos)
if min_depth < 0:
    print("context at min:", repr(src[max(0, min_pos - 80):min_pos + 80]))

depth2 = 0
min2 = 0
pos2 = 0
for i, c in enumerate(src):
    if c == '[':
        depth2 += 1
    elif c == ']':
        depth2 -= 1
        if depth2 < min2:
            min2 = depth2
            pos2 = i
print("final bracket depth:", depth2, "min:", min2, "at", pos2)
if min2 < 0:
    print("context:", repr(src[max(0, pos2 - 80):pos2 + 80]))

depth3 = 0
min3 = 0
pos3 = 0
for i, c in enumerate(src):
    if c == '{':
        depth3 += 1
    elif c == '}':
        depth3 -= 1
        if depth3 < min3:
            min3 = depth3
            pos3 = i
print("final brace depth:", depth3, "min:", min3, "at", pos3)
if min3 < 0:
    print("context:", repr(src[max(0, pos3 - 80):pos3 + 80]))
