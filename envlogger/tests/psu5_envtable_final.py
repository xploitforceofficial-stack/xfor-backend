"""Build the definitive env mapping for the PSU v5 VM.

Only consider env reads in the deserializer's top scope: local X=e[<expr>]
where expr is a numeric constant expression or a string key. Later reads
inside the interpreter loop use instruction fields (e[l], e[t]...) and must
NOT be included - they are dynamic.
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

pat = re.compile(r'local (\w)=e\[([^\]]*)\]')

envmap = {}
for m in pat.finditer(VM):
    var, expr = m.group(1), m.group(2).strip()

    if re.match(r'^[A-Za-z_]\w*$', expr) and not re.match(r"^\d+$", expr):

        sm = re.match(r"""^(['\"])([A-Za-z0-9_]+)\1$""", expr)
        if sm:
            key = sm.group(2)
            val = envtable.get(key)
            if val is not None:
                envmap[var] = _coerce(val) if False else val
        continue
    key = eval_expr(expr)
    if key is None:
        continue
    val = envtable.get(str(key))
    if val is not None:
        envmap[var] = val
    else:
        envmap[var] = None

def coerce(v):
    if v is None: return None
    try:
        return int(v)
    except ValueError:
        return v

out = {}
for k, v in envmap.items():
    if v is None:
        out[k] = None
    else:
        try:
            out[k] = int(v)
        except (ValueError, TypeError):
            out[k] = v

if out.get('y') in (0, None): out['y'] = 2
if out.get('Q') in (None, 0): out['Q'] = 52
out.pop('s', None)
out.pop('f', None)

print(json.dumps(out, indent=1))
print()
print('=== unresolved (None) vars:', [k for k, v in out.items() if v is None])

json.dump(out, open('Samples/PSU/v5/_envmap.json', 'w'), indent=1)
