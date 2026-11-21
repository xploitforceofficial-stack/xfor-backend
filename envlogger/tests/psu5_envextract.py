"""Extract the env table from the v5 tail and rebuild the candidate with it.

The tail after dup-mark had re-injected entries — those are junk duplicates. The REAL
env table entries live before the FIRST '})' close. Find where the env table opens:
'(({ [' after 'return A(I(),{},v())(...);end;' in the a region.
"""
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()
a = s[1000532:1005928]
b = s[1005930:]
v = a + ']]' + b

key = 'return A(I(),{},v())(...);end;'
i = v.find(key)
print('call site at', i)
env_open = v.find('(({', i)
print('env open at', env_open, repr(v[env_open:env_open+80]))

env_close = v.find('})', env_open)
print('env close at', env_close, repr(v[env_close-60:env_close+40]))

env_entries = v[env_open+3:env_close]
print('env entries len:', len(env_entries))
print('first 200:', repr(env_entries[:200]))
print('last 200:', repr(env_entries[-200:]))
