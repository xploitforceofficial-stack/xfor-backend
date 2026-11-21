"""Extract and statically evaluate the PSU v5 env table (pure constants)."""
import json
import re
import sys

s = open('Samples/PSU/v5/1.lua', encoding='utf-8', errors='replace').read()

anchor = s.find('end)(({')
print("anchor at:", anchor, repr(s[anchor - 40:anchor + 60]))

def skip_string(i):
    """s[i] is a quote or [ of a long string; return index just past it."""
    c = s[i]
    if c in '"\'':
        j = i + 1
        while j < len(s):
            if s[j] == '\\':
                j += 2
                continue
            if s[j] == c:
                return j + 1
            j += 1
        return len(s)

    eq = 0
    j = i + 1
    while j < len(s) and s[j] == '=':
        eq += 1
        j += 1
    if j < len(s) and s[j] == '[':
        close = ']' + '=' * eq + ']'
        k = s.find(close, j + 1)
        return (k + len(close)) if k != -1 else len(s)
    return i + 1

def skip_comment(i):
    """s[i:i+2] == '--'; return index just past the comment."""
    j = i + 2
    if j < len(s) and s[j] == '[':
        eq = 0
        k = j + 1
        while k < len(s) and s[k] == '=':
            eq += 1
            k += 1
        if k < len(s) and s[k] == '[':
            close = ']' + '=' * eq + ']'
            f = s.find(close, k + 1)
            return (f + len(close)) if f != -1 else len(s)
    while j < len(s) and s[j] != '\n':
        j += 1
    return j

i = anchor + 4
depth = 0
close_pos = -1
while i < len(s):
    c = s[i]
    if c in '"\'':
        i = skip_string(i)
        continue
    if s[i:i + 2] == '--':
        i = skip_comment(i)
        continue
    if c == '[' and i + 1 < len(s) and s[i + 1] in '=[':

        eq = 0
        j = i + 1
        while j < len(s) and s[j] == '=':
            eq += 1
            j += 1
        if j < len(s) and s[j] == '[':
            i = skip_string(i)
            continue
    if c in '({[':
        depth += 1
    elif c in ')}]':
        depth -= 1
        if depth == 0:
            close_pos = i
            break
    i += 1

print("balanced close at:", close_pos)
print("tail after close:", repr(s[close_pos:close_pos + 120]))

table_src = s[anchor + 5:close_pos + 1]

table_src = s[anchor + 5:close_pos + 1]

open('Samples/PSU/v5/_envtable_raw.txt', 'w', encoding='utf-8').write(table_src)
print("raw table src len:", len(table_src))
print("head:", repr(table_src[:150]))
print("tail:", repr(table_src[-150:]))
