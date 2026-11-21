"""Rebuild final v2: body needs l (the xor bitop) which lived in the scrambled
prologue. Cut at 'local function o(' AND inject l into the prelude."""
s = open('Samples/PSU/v5/1.lua', encoding='utf-8', errors='replace').read()

VM = s[1000524:]
idx = VM.find('local function o(')
body = VM[idx:]

prelude = """local f = function(e, ...)
local u, c, n = PSU_PAYLOAD, 1, 0
local p, s = string.byte, string.sub
local x = {}
for i = 0, 255 do x[i] = string.char(i) end
local function l(a, b)
local r, m = 0, 1
while a > 0 or b > 0 do
if (a % 2) ~= (b % 2) then r = r + m end
a = math.floor(a / 2)
b = math.floor(b / 2)
m = m * 2
end
return r
end
"""

rebuilt = prelude + body
open('Samples/PSU/v5/_rebuilt_final.lua', 'w', encoding='utf-8').write(rebuilt)
print('len:', len(rebuilt))
