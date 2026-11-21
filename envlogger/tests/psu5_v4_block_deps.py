"""Find free (unbound) single-letter variables in v4's deserializer block: these are upvalues
defined in the outer wrapper that the block needs. Extract their definitions from v4's head."""
import re

v4 = open('Samples/PSU/v4/1.lua', encoding='utf-8', errors='replace').read()
st = v4.find('local M=')
en = v4.find(',(#R-G);')
block = v4[st:en]

idents = set(re.findall(r'\b([a-zA-Z_]\w*)\b', block))

bound = set(re.findall(r'local\s+([a-zA-Z_]\w*)', block))
for m in re.finditer(r'local\s+([a-zA-Z_]\w*(?:\s*,\s*[a-zA-Z_]\w*)*)\s*=', block):
    for nm in m.group(1).split(','):
        bound.add(nm.strip())

for m in re.finditer(r'function\s*\(([^)]*)\)', block):
    for nm in m.group(1).split(','):
        nm = nm.strip().replace('...', '')
        if nm:
            bound.add(nm)
for m in re.finditer(r'for\s+([a-zA-Z_]\w*)(?:\s*,\s*([a-zA-Z_]\w*))?(?:\s*,\s*([a-zA-Z_]\w*))?\s+(?:in|=)', block):
    for g in m.groups():
        if g:
            bound.add(g)

free = idents - bound

LUA_GLOBALS = {'string', 'math', 'table', 'os', 'pcall', 'pairs', 'ipairs', 'tostring', 'tonumber',
               'getfenv', 'setmetatable', 'rawget', 'select', 'unpack', 'type', 'error', 'assert',
               'sub', 'char', 'byte', 'concat', 'insert', 'floor', 'format', 'print', 'return',
               'then', 'end', 'do', 'and', 'or', 'not', 'nil', 'true', 'false', 'while', 'if',
               'elseif', 'else', 'for', 'in', 'function', 'local', 'repeat', 'until', 'break'}
free = {f for f in free if f not in LUA_GLOBALS and len(f) <= 2}
print("free single-letter vars the block needs from outer scope:")
print(sorted(free))
print()

head = v4[:st]
print("=== definitions of those names in v4 head:")
for nm in sorted(free):
    m = re.search(rf'local\s+{nm}\s*=\s*(.{{0,120}})', head)
    if m:
        print(f"  {nm} = {m.group(1)!r}")
    else:
        print(f"  {nm} = ??? NOT FOUND in head")
