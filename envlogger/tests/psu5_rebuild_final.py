"""Final rebuild: body = everything up to 'return A(...)(...);end', dropping the
inline env-table call glue (we supply env via JSON instead)."""
body = open('Samples/PSU/v5/_rebuilt_full2.lua', encoding='utf-8').read()
marker = 'return A(I(),{},v())(...);end)'
i = body.find(marker)
assert i > 0
cut = body[:i + len(marker) - 1]
open('Samples/PSU/v5/_rebuilt_final.lua', 'w', encoding='utf-8').write(cut)
print('len:', len(cut))
print('tail:', repr(cut[-80:]))
