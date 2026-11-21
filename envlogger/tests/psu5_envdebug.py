"""Debug the env table entry parsing - show failures."""
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
            if c2 == '[':
                depth2 += 1
            elif c2 == ']':
                depth2 -= 1
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

def parse_value(v):
    v = v.strip()
    m = re.match(r'^"((?:[^"\\]|\\.)*)"$', v)
    if m:
        raw = m.group(1)
        out = []
        k = 0
        while k < len(raw):
            c = raw[k]
            if c == '\\' and k + 1 < len(raw):
                k += 1
                e = raw[k]
                if e == 'n':
                    out.append('\n')
                elif e == 't':
                    out.append('\t')
                elif e == 'r':
                    out.append('\r')
                elif e == '\\':
                    out.append('\\')
                elif e == '"':
                    out.append('"')
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
    except Exception as ex:
        return ('FAIL', v2[:60])

ok = 0
fails = []
for e in entries:
    e = e.strip()
    if not e:
        continue
    m = re.match(r'^\[([^\]]*)\]\s*=\s*(.+)$', e, re.S)
    if not m:
        fails.append(('NOKEY', e[:80]))
        continue
    kexpr, vexpr = m.group(1).strip(), m.group(2).strip()
    key = parse_value(kexpr)
    val = parse_value(vexpr)
    if isinstance(key, tuple) or isinstance(val, tuple):
        fails.append((key if isinstance(key, tuple) else val, e[:100]))
    else:
        ok += 1

print('parsed:', ok, 'failed:', len(fails))
for f in fails[:15]:
    print(' FAIL:', f)
