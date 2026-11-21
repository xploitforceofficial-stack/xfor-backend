"""Fix env eval: handle nested parens like ((#{...}+N-#("str"))) correctly."""
import json
import re

s = open('Samples/PSU/v5/1.lua', encoding='utf-8', errors='replace').read()
env = json.load(open('Samples/PSU/v5/_envtable.json'))

VM = s[1000524:]

pat = re.compile(r'local (\w)=e\[')

def eval_expr(expr):
    """Evaluate a Lua env expression: numbers, +, -, #{...}, #("..."), #('...'), parens."""
    e = expr.strip()

    def count_repl(m2):
        inner = m2.group(1)
        parts = [p for p in inner.split(';') if p.strip()]
        return str(len(parts))
    e = re.sub(r'#\{([^}]*)\}', count_repl, e)

    e = re.sub(r'#\("([^"]*)"\)', lambda m2: str(len(m2.group(1))), e)
    e = re.sub(r"#\('([^']*)'\)", lambda m2: str(len(m2.group(1))), e)

    e = e.replace('(', ' ').replace(')', ' ')
    try:
        return int(eval(e))
    except Exception:
        return None

results = {}
for m in pat.finditer(VM):
    var = m.group(1)
    start = m.end()
    depth = 1
    i = start
    while i < len(VM) and depth > 0:
        c = VM[i]
        if c == '[': depth += 1
        elif c == ']': depth -= 1
        i += 1
    expr = VM[start:i-1]
    key = eval_expr(expr)
    envval = env.get(str(key)) if key is not None else None
    results[var] = (key, envval)

print(f'{len(results)} env locals:')
for var, (key, val) in results.items():
    print(f'  {var} = key {key} -> {val!r}')
