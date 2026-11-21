"""Add stdlib function bindings to the env map for keys the VM calls.

From usage analysis of the v5 VM body:
- T ('FJ3bzQ5i0j') = select           (select('#',...) count idiom at lines 78/248)
- V ('QCl5H')      = setmetatable     (V({}, {__index=...}) at line 1088)
- D                = math.floor-ish? D(n*t) at float decode: likely math.floor
   (D is an upvalue defined in body? No: D appears only at 133/142 - check)
- K                = ldexp-like? K(n,l-P) at line 141 - exponent apply
"""
import json

env = json.load(open('Samples/PSU/v5/_envmap.json'))

FN_BINDINGS = {
    'FJ3bzQ5i0j': 'select',
    'QCl5H': 'setmetatable',
    'udTlwPHfj': 'tostring',
    'jI8GuSjfMf': 'getfenv',
}

json.dump(FN_BINDINGS, open('Samples/PSU/v5/_fnbindings.json', 'w'), indent=1)
print('bindings:', FN_BINDINGS)

import re
body = open('Samples/PSU/v5/_lineated.lua', encoding='utf-8').read()
for nm in ['K', 'D']:
    defs = [ln for ln in body.split('\n') if re.search(r'local function ' + nm + r'\b|local ' + nm + r'\s*=', ln)]
    print(nm, 'defs in body:', defs[:2])
