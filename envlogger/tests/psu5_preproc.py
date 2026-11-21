"""Build the v5 candidate: drop the troll head (chars 0..282), keep the long string
as a plain data string, then the tail from 1005928 (after ]] close) — wrap it all in
the v4.5-style wrapper so luaparse accepts it.

Structure we build:
  for l,e in pairs({(function(e,...) local P=<payload string>; <tail code from 1005928, minus the final '}),...])})do return e end'> end)(({...}),...) }) do return e end
"""
s = open('Samples/PSU/v5/1.lua', encoding='latin1').read()

lstr_open = 283
lstr_close_end = 1005930
payload = s[lstr_open + 2:1005928]
tail = s[lstr_close_end:]

print('payload len:', len(payload))
print('tail len:', len(tail))
print('tail head:', repr(tail[:80]))
print('tail end:', repr(tail[-80:]))

out = 'for l,e in pairs({(function(e,...) local u=[[DEBUG_NOP]];' + tail + '\nend)(({'

out += '}),...)}) do return e end;'

open('Samples/PSU/v5/_v5cand.lua', 'w', encoding='latin1').write(out)
print('wrote _v5cand.lua, len', len(out))
