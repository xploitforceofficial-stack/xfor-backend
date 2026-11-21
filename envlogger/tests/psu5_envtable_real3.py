"""Final env eval with function-call count support and string keys."""
import json
import re

s = open('Samples/PSU/v5/1.lua', encoding='utf-8', errors='replace').read()
env = json.load(open('Samples/PSU/v5/_envtable.json'))

VM = s[1000524:]

pat = re.compile(r'local (\w)=e\[')

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

results = {}
order = []
for m in pat.finditer(VM):
    var = m.group(1)
    start = m.end()
    depth = 1; i = start
    while i < len(VM) and depth > 0:
        c = VM[i]
        if c == '[': depth += 1
        elif c == ']': depth -= 1
        i += 1
    expr = VM[start:i-1].strip()

    sm = re.match(r"""^(['\"])([A-Za-z0-9_]+)\1$""", expr)
    if sm:
        key = sm.group(2)
        val = env.get(key)
        results[var] = (key, val)
    else:
        key = eval_expr(expr)
        val = env.get(str(key)) if key is not None else None
        results[var] = (key, val)
    order.append(var)

print(f'{len(results)} env locals:')
for var in order:
    key, val = results[var]
    print(f'  {var} = {key!r} -> {val!r}')
