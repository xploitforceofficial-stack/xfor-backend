import re

s = open('envlogger/src/env/roblox.luau', encoding='utf-8').read()
i = s.find('globals.debug = {')
j = i + len('globals.debug = {')
depth = 1
k = j
while k < len(s) and depth:
    if s[k] == '{': depth += 1
    elif s[k] == '}': depth -= 1
    k += 1
block = s[j:k-1]

keys = []
for ln in block.split('\n'):
    m = re.match(r'^(\t+)([A-Za-z_]\w*)\s*=\s*(.*)', ln)
    if m and len(m.group(1)) == 2:
        keys.append(m.group(2))
print('debug keys (%d):' % len(keys))
for k in keys:
    print(' ', k)

required = ['dumpheap', 'getconstants', 'getproto', 'setmemorycategory', 'profilebegin', 'loadmodule',
            'traceback', 'getstack', 'getregistry', 'setmetatable', 'getupvalues', 'getupvalue',
            'getmemorycategory', 'resetmemorycategory', 'setupvalue', 'validlevel', 'isvalidlevel',
            'dumpcodesize', 'setstack', 'getconstant', 'profileend', 'info', 'getinfo', 'getprotos',
            'setconstant', 'getmetatable', 'dumprefs']
have = set(keys)
missing = [k for k in required if k not in have]
print()
print('missing from our debug (%d):' % len(missing))
for k in missing:
    print(' ', k)
extra = [k for k in keys if k not in required and k not in ('hookCallback',)]
print()
print('extra keys we have that fixture does not list (%d):' % len(extra))
for k in extra:
    print(' ', k)
