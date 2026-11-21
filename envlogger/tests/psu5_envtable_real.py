"""Evaluate the REAL env table from the original v5 file.

The env reads look like: e[((668151090-#(\"troll string\")))] or e[(12345)] or
e[((#{1;2;3}+12345))]. We need to compute each key by evaluating the troll
string lengths, then look up the value in the JSON envtable.
"""
import json
import re

s = open('Samples/PSU/v5/1.lua', encoding='utf-8', errors='replace').read()
env = json.load(open('Samples/PSU/v5/_envtable.json'))

VM = s[1000524:]

pat = re.compile(r'local (\w)=e\[')
results = {}
for m in pat.finditer(VM):
    var = m.group(1)
    start = m.end()

    depth = 1
    i = start
    while i < len(VM) and depth > 0:
        c = VM[i]
        if c == '[':
            depth += 1
        elif c == ']':
            depth -= 1
        i += 1
    expr = VM[start:i-1]

    def eval_expr(e):

        def count_repl(m2):
            inner = m2.group(1)
            parts = [p for p in inner.split(';') if p.strip()]
            return str(len(parts))
        e2 = re.sub(r'#\{([^}]*)\}', count_repl, e)

        def strlen_repl(m2):
            return str(len(m2.group(1)))
        e2 = re.sub(r'#\("([^"]*)"\)', strlen_repl, e2)
        e2 = re.sub(r"#\('([^']*)'\)", strlen_repl, e2)

        e2 = e2.strip()
        while e2.startswith('(') and e2.endswith(')'):
            e2 = e2[1:-1].strip()

        try:
            return int(eval(e2))
        except Exception as ex:
            return None
    val = eval_expr(expr)
    if val is not None:
        envval = env.get(str(val))
        results[var] = (val, envval)
    else:
        results[var] = (None, None)

print(f'{len(results)} env locals:')
for var, (key, val) in results.items():
    print(f'  {var} = key {key} -> {val!r}')
