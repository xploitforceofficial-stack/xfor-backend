"""Final fn bindings for the v5 harness env.

Usage-derived stdlib mappings:
- T ('FJ3bzQ5i0j') = select         : select('#',...) count idiom
- V ('QCl5H')      = setmetatable   : V({}, {__index=...})
- K (key 130212618 -> 'n'? no...)   : used as K(n, l-P) applying exponent -
                                      math.ldexp(n, exp) matches float decode
- D                = math.floor     : D(n*t) truncation in float decode
- G ('udTlwPHfj')  = tostring       : speculative, harmless
- P ('jI8GuSjfMf') = 1023           : already numeric (mantissa bias) - KEEP numeric
"""
import json

env = json.load(open('Samples/PSU/v5/_envmap.json'))

FN_BINDINGS = {
    'FJ3bzQ5i0j': 'select',
    'QCl5H': 'setmetatable',
    'udTlwPHfj': 'tostring',
}

import re
lineated = open('Samples/PSU/v5/_lineated.lua', encoding='utf-8').read()

json.dump(FN_BINDINGS, open('Samples/PSU/v5/_fnbindings.json', 'w'), indent=1)
print('fn bindings:', FN_BINDINGS)

print('K, D -> provide as globals: math.ldexp, math.floor')
