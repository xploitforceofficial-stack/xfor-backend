local Sandbox = require("../src/core/sandbox")
local fs = require("@lune/fs")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec2.lua")
local result = Sandbox.run(src, { timeout = 200, maxExplored = 0 })
print("200s:", "ok=" .. tostring(result.ok), "err=" .. tostring(result.err):sub(1, 100), "dec=" .. tostring(result.decryptedStringCount))
local out = {}
for _, e in ipairs(result.outputs or {}) do out[#out+1] = e.text end
print("outputs:", table.concat(out, " | "):sub(1, 200))
