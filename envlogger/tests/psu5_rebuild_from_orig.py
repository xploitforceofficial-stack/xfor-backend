"""Rebuild v5 body from ORIGINAL VM text (strings intact).

Structure of the rebuilt file:
  local f = function(e, ...)          -- e = env table (from bootstrap call)
      <prelude>                        -- u,c,n,p,s,x  (payload stream state)
      <original VM text>               -- function o, env reads, i/d/f/a readers,
                                        -- deserializer, interpreter, return A(I(),{},v())(...)
  end
  return f

The original VM text starts mid-expression: 'P-(90));local function o(...'
We cut at 'local function o(' and prepend a prelude that defines everything
the text references before that point - which is nothing (P-(90) is the tail
of a broken expression we drop).
"""
import json, re

s = open('Samples/PSU/v5/1.lua', encoding='utf-8', errors='replace').read()
payload = open('Samples/PSU/v5/_vmpayload.txt', encoding='utf-8').read()

VM = s[1000524:]
idx = VM.find('local function o(')
body = VM[idx:]

assert 'PSU_STR' not in body, 'unexpected placeholder'

print('tail:', repr(body[-80:]))

prelude = """local u, c, n = PSU_PAYLOAD, 1, 0
local p, s = string.byte, string.sub
local x = {}
for i = 0, 255 do x[i] = string.char(i) end
"""

rebuilt = "local f = function(e, ...)\n" + prelude + body
open('Samples/PSU/v5/_rebuilt_full2.lua', 'w', encoding='utf-8').write(rebuilt)
print('rebuilt len:', len(rebuilt))
print('head:', repr(rebuilt[:200]))
