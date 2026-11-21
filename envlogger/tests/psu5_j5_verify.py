"""Verify j5 has the real env entries and check whether the VM code references the
payload blob (the 500KB string). In j5, is the 500KB blob present anywhere? The
deserializer needs 'u' — find how u would be bound: via the wrapper '...' args or
env table? Check j5 for the payload string and for 'u' initialization."""
s = open('Samples/PSU/v5/_v5cand_j5.lua', encoding='latin1').read()

print('has PSU| blob:', 'PSU|RxlsbeYA' in s)
print('env entries present:', '289639432' in s)
print()

i = s.find('local function _(')
print('_ at', i, repr(s[i:i+120]))

import re
for m in re.finditer(r'return\(_\(', s):
    print('_( call at', m.start(), repr(s[m.start():m.start()+80]))
