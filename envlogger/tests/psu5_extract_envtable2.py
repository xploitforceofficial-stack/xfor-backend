"""Extract just the first balanced {...} table from the env-table region and eval it in Lua semantics."""
import json

s = open('Samples/PSU/v5/1.lua', encoding='utf-8', errors='replace').read()

anchor = s.find('end)(({')
start = anchor + 6

def scan(i):
    depth = 0
    while i < len(s):
        c = s[i]
        if c == '"':
            i += 1
            while i < len(s):
                if s[i] == '\\':
                    i += 2
                    continue
                if s[i] == '"':
                    i += 1
                    break
                i += 1
            continue
        if c == "'":
            i += 1
            while i < len(s):
                if s[i] == '\\':
                    i += 2
                    continue
                if s[i] == "'":
                    i += 1
                    break
                i += 1
            continue
        if s[i:i + 2] == '--':
            j = i + 2
            while j < len(s) and s[j] != '\n':
                j += 1
            i = j
            continue
        if c == '[':
            eq = 0
            j = i + 1
            while j < len(s) and s[j] == '=':
                eq += 1
                j += 1
            if j < len(s) and s[j] == '[':
                close = ']' + '=' * eq + ']'
                k = s.find(close, j + 1)
                i = (k + len(close)) if k != -1 else len(s)
                continue
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1

close = scan(start)
print("table close at:", close)
table = s[start:close + 1]
print("table len:", len(table))
open('Samples/PSU/v5/_envtable1.lua', 'w', encoding='utf-8').write('return ' + table)

print("after close:", repr(s[close + 1:close + 120]))
