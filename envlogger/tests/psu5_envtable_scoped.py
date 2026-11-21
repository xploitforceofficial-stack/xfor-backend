"""Scoped envmap: keep the FIRST value assigned to each var in declaration order
(the one live when the reader functions are defined). Emit JSON.
"""
import json
import re

s = open('Samples/PSU/v5/1.lua', encoding='utf-8', errors='replace').read()
envtable = json.load(open('Samples/PSU/v5/_envtable.json'))
VM = s[1000524:]

def eval_expr(expr):
    e = expr.strip()
    def fn_repl(m2):
        ret = m2.group(1)
        vals = [v for v in re.split(r'[,;]', ret) if v.strip()]
        return str(len(vals))
    e = re.sub(r'\(function\([^)]*\)\s*return\s+([^;}]+)[;}]?\s*end\)\(\)', fn_repl, e)
    def count_repl(m2):
        inner = m2.group(1)
        parts = [p for p in inner.split(';') if p.strip()]
        return str(len(parts))
    e = re.sub(r'#\{([^{}]*)\}', count_repl, e)
    e = re.sub(r'#\("([^"]*)"\)', lambda m2: str(len(m2.group(1))), e)
    e = re.sub(r"#\('([^']*)'\)", lambda m2: str(len(m2.group(1))), e)
    e = e.replace('(', ' ').replace(')', ' ')
    try:
        return int(eval(e))
    except Exception:
        return None

cut = VM.find('local function i(')
PRELUDE = VM[:cut]

pat = re.compile(r"local (\w)=e\[(.+?)\](?=;local|\Z)")

scoped = {}
dupes = []
for m in pat.finditer(PRELUDE):
    var, expr = m.group(1), m.group(2).strip()
    sm = re.match(r"""^(['\"])([A-Za-z0-9_]+)\1$""", expr)
    if sm:
        key, val = sm.group(2), envtable.get(sm.group(2))
    elif re.match(r'^-?\d+$', expr):
        key, val = int(expr), envtable.get(expr)
    else:
        key = eval_expr(expr)
        val = envtable.get(str(key)) if key is not None else None
    if val is None:
        dupes.append((var, expr[:60], key))
        continue
    if var in scoped:
        dupes.append((var, expr[:60], key))
        continue
    try:
        scoped[var] = int(val)
    except (ValueError, TypeError):
        scoped[var] = val

print(json.dumps(scoped, indent=1))
print()
print('unresolved:', dupes)

json.dump(scoped, open('Samples/PSU/v5/_envmap.json', 'w'), indent=1)
