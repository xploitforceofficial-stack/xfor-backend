"""Final env table parser: proper token-level handling of the inline env table."""
import json, re

s = open('Samples/PSU/v5/1.lua', encoding='utf-8', errors='replace').read()
i = s.find('end)(({')
tail = s[i + len('end)('):]
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

entries = []
buf = []
in_str = None
k = 0
brk = 0
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
        brk += 1
        buf.append(c)
    elif c == ']':
        brk -= 1
        buf.append(c)
    elif c == ';' and brk == 0:
        entries.append(''.join(buf))
        buf = []
    else:
        buf.append(c)
    k += 1
if buf:
    entries.append(''.join(buf))

def unescape(raw):
    out = []
    k = 0
    while k < len(raw):
        c = raw[k]
        if c == '\\' and k + 1 < len(raw):
            k += 1
            e = raw[k]
            if e == 'n': out.append('\n')
            elif e == 't': out.append('\t')
            elif e == 'r': out.append('\r')
            elif e == '\\': out.append('\\')
            elif e == '"': out.append('"')
            elif e == "'": out.append("'")
            elif e.isdigit():
                num = ''
                while k < len(raw) and raw[k].isdigit() and len(num) < 3:
                    num += raw[k]
                    k += 1
                out.append(chr(int(num)))
                continue
            else:
                out.append(e)
        else:
            out.append(c)
        k += 1
    return ''.join(out)

def parse_value(v):
    v = v.strip()
    m = re.match(r'^"((?:[^"\\]|\\.)*)"$', v, re.S)
    if m:
        return unescape(m.group(1))
    m = re.match(r"^'((?:[^'\\]|\\.)*)'$", v, re.S)
    if m:
        return unescape(m.group(1))
    v2 = v
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
    v2 = re.sub(r'#\(\s*"([^"]*)"\s*\)', lambda m2: str(len(m2.group(1))), v2)
    v2 = re.sub(r"#\(\s*'([^']*)'\s*\)", lambda m2: str(len(m2.group(1))), v2)
    v2 = v2.replace('(', ' ').replace(')', ' ')

    try:
        return int(eval(v2))
    except Exception:
        return None

env = {}
dupes = 0
unparsed = 0
for e in entries:
    e = e.strip()
    if not e:
        continue
    if not e.startswith('['):

        m2 = re.match(r'^([A-Za-z0-9_]+)\s*=\s*(.+)$', e, re.S)
        if m2:
            key = m2.group(1)
            val = parse_value(m2.group(2))
            if key not in env and val is not None:
                env[key] = val
            else:
                unparsed += 1
        else:
            unparsed += 1
        continue

    depth2 = 1
    p = 1
    while p < len(e) and depth2 > 0:
        if e[p] == '[': depth2 += 1
        elif e[p] == ']': depth2 -= 1
        p += 1
    kexpr = e[1:p-1].strip()
    rest = e[p:].strip()
    assert rest.startswith('='), rest[:40]
    vexpr = rest[1:].strip()
    key = parse_value(kexpr)
    val = parse_value(vexpr)
    if key is None or val is None:
        unparsed += 1
        continue
    if key in env:
        dupes += 1
        continue
    env[key] = val

print('parsed:', len(env), 'dupes:', dupes, 'unparsed:', unparsed)
json.dump(env, open('Samples/PSU/v5/_envmap.json', 'w'), indent=1)

for k in ['666514067', '909610532', '822479318', '190638666', '994620601', '501321']:
    print(k, '->', repr(env.get(int(k)) if k.isdigit() else k))
