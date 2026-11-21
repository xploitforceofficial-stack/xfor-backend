import re

REQUIRED = {
    'utf8': ['offset', 'codepoint', 'nfdnormalize', 'char', 'codes', 'len', 'graphemes', 'nfcnormalize', 'charpattern'],
    'math': ['log', 'e', 'ldexp', 'deg', 'cosh', 'round', 'random', 'frexp', 'tanh', 'floor', 'max', 'sqrt', 'modf', 'huge', 'sqrt2', 'pow', 'isnan', 'acos', 'phi', 'tau', 'exp', 'pi', 'isfinite', 'tan', 'cos', 'isinf', 'atan', 'map', 'sign', 'ceil', 'clamp', 'noise', 'abs', 'nan', 'sinh', 'asin', 'min', 'randomseed', 'fmod', 'rad', 'atan2', 'log10', 'sin', 'lerp'],
    'debug': ['dumpheap', 'getconstants', 'getproto', 'setmemorycategory', 'profilebegin', 'loadmodule', 'traceback', 'getstack', 'getregistry', 'setmetatable', 'getupvalues', 'getupvalue', 'getmemorycategory', 'resetmemorycategory', 'setupvalue', 'validlevel', 'isvalidlevel', 'dumpcodesize', 'setstack', 'getconstant', 'profileend', 'info', 'getinfo', 'getprotos', 'setconstant', 'getmetatable', 'dumprefs'],
    'task': ['defer', 'cancel', 'wait', 'desynchronize', 'synchronize', 'delay', 'spawn'],
}

import subprocess, os

probe = '''
local out = {}
for k, v in utf8 do out[#out+1] = k end
print(table.concat(out, ","))
for k, v in math do out[#out+1] = "M:" .. k end
print(table.concat(out, ","))
'''
open('envlogger/tests/at5_libkeys.luau', 'w').write(probe)
res = subprocess.run(['lune', 'run', 'tests/at5_libkeys'], cwd='envlogger', capture_output=True, text=True, timeout=60)
lines = res.stdout.strip().split('\n')
utf8_keys = set(lines[0].split(',')) if lines else set()
all_keys = set(lines[1].split(',')) if len(lines) > 1 else set()
math_keys = {k[2:] for k in all_keys if k.startswith('M:')}
utf8_keys = {k for k in utf8_keys if not k.startswith('M:')}

print('Lune utf8 keys:', sorted(utf8_keys))
print('Lune math keys:', sorted(math_keys))
print()

for lib in ('utf8', 'math'):
    missing = [k for k in REQUIRED[lib] if k not in utf8_keys]
    print(lib, 'missing:', missing)
    print()

s = open('envlogger/src/env/stdlib.luau', encoding='utf-8').read()
i = s.find('local function buildTask')
block = s[i:i+12000]
task_keys = re.findall(r'^\t\t([a-z]\w*)\s*=\s*function', block, re.M)
print('our task keys:', task_keys)
missing = [k for k in REQUIRED['task'] if k not in task_keys]
print('task missing:', missing)
print()

math_built = set(math_keys)
for m in re.finditer(r'out\.(\w+)\s*=', s[:i+12000]):
    math_built.add(m.group(1))
print('our math (lifted + custom):', sorted(math_built))
missing = [k for k in REQUIRED['math'] if k not in math_built]
print('math missing:', missing)
