"""v5 VM body symbol analysis: defined locals vs free references."""
import re

body = open('Samples/PSU/v5/_vmcode.lua', encoding='utf-8', errors='replace').read()

def strip_strings(src):
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
            while j < n and src[j] != '\n':
                j += 1
            i = j
        elif c in ' \t\r\n':
            out.append('')
            i += 1
        else:
            out.append(c)
            i += 1
    return ''.join(out)

clean = strip_strings(body)
open('Samples/PSU/v5/_vmcode_clean.lua', 'w', encoding='utf-8').write(clean)
print("clean body len:", len(clean))

defined = set()
for m in re.finditer(r'local\s+([a-zA-Z_]\w*)', clean):
    defined.add(m.group(1))
for m in re.finditer(r'local\s+([a-zA-Z_]\w*(?:\s*,\s*[a-zA-Z_]\w*)*)\s*=', clean):
    for nm in m.group(1).split(','):
        defined.add(nm.strip())
for m in re.finditer(r'function\s+([a-zA-Z_]\w*)\s*\(', clean):
    defined.add(m.group(1))
for m in re.finditer(r'function\s*\(([^)]*)\)', clean):
    for nm in m.group(1).split(','):
        nm = nm.strip().replace('...', '').strip()
        if nm:
            defined.add(nm)
for m in re.finditer(r'for\s+([a-zA-Z_]\w*)\s*[,=]', clean):
    defined.add(m.group(1))
    if m.group(0).rstrip().endswith(','):
        pass

used = set(re.findall(r'\b([a-zA-Z_]\w*)\b', clean))

KEYWORDS = {'local', 'function', 'end', 'if', 'then', 'else', 'elseif', 'for', 'while', 'do',
            'return', 'and', 'or', 'not', 'nil', 'true', 'false', 'break', 'in', 'repeat', 'until',
            'nil'}
LUA_STD = {'string', 'math', 'table', 'os', 'pcall', 'xpcall', 'pairs', 'ipairs', 'next', 'tostring',
           'tonumber', 'getfenv', 'setfenv', 'setmetatable', 'getmetatable', 'rawget', 'rawset',
           'rawequal', 'select', 'unpack', 'type', 'typeof', 'error', 'assert', 'print', 'coroutine',
           'bit32', 'buffer', 'vector', 'tick', 'wait', 'game', 'script', 'shared', 'workspace',
           'Instance', 'Vector3', 'CFrame', 'loadstring', 'require', 'collectgarbage', '_G', '_ENV'}

free = used - defined - KEYWORDS - LUA_STD

free_short = sorted(f for f in free if len(f) <= 8)
print("defined locals:", sorted(defined))
print()
print("FREE references (needs from wrapper/env):", free_short)
print()

for nm in free_short[:30]:
    ctx = re.findall(rf'.{{25}}\b{nm}\b.{{25}}', clean)
    print(f"{nm}: {ctx[0] if ctx else '?'}")
