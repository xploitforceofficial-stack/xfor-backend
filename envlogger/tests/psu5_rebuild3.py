"""Rebuild v5 FINAL: the file's real shape is

    (function(e, ...)  <VM body>  end)( ({...inline env table...}), ... )

The inline env table has escaped byte-string values ("\\114" = 'r'), numeric keys
from expressions, and duplicate trailing entries (troll). Extract the table,
evaluate it, and emit both the env JSON and a rebuilt body whose bootstrap call
uses the evaluated env.
"""
import json, re

s = open('Samples/PSU/v5/1.lua', encoding='utf-8', errors='replace').read()

i = s.find('end)(({')
tail = s[i + len('end)('):]

assert tail[0] == '(' and tail[1] == '{'
start = 1
depth = 0
j = start
in_str = None
while j < len(tail):
    c = tail[j]
    if in_str:
        if c == '\\':
            j += 2
            continue
        if c == in_str:
            in_str = None
    else:
        if c in '"\'':
            in_str = c
        elif c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                break
    j += 1

table_text = tail[start:j+1]
print('table len:', len(table_text))

def parse_value(v):
    v = v.strip()

    m = re.match(r'^"((?:[^"\\]|\\.)*)"$', v)
    if m:
        raw = m.group(1)

        out = []
        k = 0
        while k < len(raw):
            c = raw[k]
            if c == '\\':
                k += 1
                e = raw[k]
                if e == 'n': out.append('\n')
                elif e == 't': out.append('\t')
                elif e == 'r': out.append('\r')
                elif e.isdigit():
                    num = raw[k:k+3]
                    out.append(chr(int(num)))
                    k += 2
                else: out.append(e)
            else:
                out.append(c)
            k += 1
        return ''.join(out)

    v2 = v.strip('()')
    def fn_repl(m2):
        ret = m2.group(1)
        vals = [x for x in re.split(r'[,;]', ret) if x.strip()]
        return str(len(vals))
    v2 = re.sub(r'\(function\([^)]*\)\s*return\s+([^;}]+)[;}]?\s*end\)\(\)', fn_repl, v2)
    def count_repl(m2):
        inner = m2.group(1)
        parts = [p for p in inner.split(';') if p.strip()]
        return str(len(parts))
    v2 = re.sub(r'#\{([^{}]*)\}', count_repl, v2)
    v2 = re.sub(r'#\("([^"]*)"\)', lambda m2: str(len(m2.group(1))), v2)
    v2 = re.sub(r"#\('([^']*)'\)", lambda m2: str(len(m2.group(1))), v2)
    v2 = v2.replace('(', ' ').replace(')', ' ')
    try:
        return int(eval(v2))
    except Exception:
        return None

env = {}
dupes = 0

entries = []
buf = []
in_str = None
k = 0
while k < len(table_text):
    c = table_text[k]
    if in_str:
        buf.append(c)
        if c == '\\':
            buf.append(table_text[k+1])
            k += 2
            continue
        if c == in_str:
            in_str = None
    elif c in '"\'':
        in_str = c
        buf.append(c)
    elif c == '[':
        depth2 = 1
        buf.append(c)
        k += 1
        while k < len(table_text) and depth2 > 0:
            c2 = table_text[k]
            buf.append(c2)
            if c2 == '[': depth2 += 1
            elif c2 == ']': depth2 -= 1
            k += 1
        continue
    elif c == ';':
        entries.append(''.join(buf))
        buf = []
    else:
        buf.append(c)
    k += 1
if buf:
    entries.append(''.join(buf))

print('entries:', len(entries))
for e in entries:
    e = e.strip()
    if not e:
        continue

    m = re.match(r'^\[([^\]]*)\]\s*=\s*(.+)$', e, re.S)
    if not m:
        continue
    kexpr, vexpr = m.group(1).strip(), m.group(2).strip()

    km = re.match(r'^"((?:[^"\\]|\\.)*)"$', kexpr)
    if km:
        key = parse_value('"' + km.group(1) + '"')
    else:
        key = parse_value(kexpr)
    val = parse_value(vexpr)
    if key is None or val is None:
        continue
    if key in env:
        dupes += 1
        continue
    env[key] = val

print('parsed env entries:', len(env), 'dupes skipped:', dupes)
print('sample:', dict(list(env.items())[:8]))
json.dump(env, open('Samples/PSU/v5/_envmap.json', 'w'), indent=1)
