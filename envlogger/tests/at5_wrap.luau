local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")
local source = fs.readFile("tests/at5_fixture_all.lua")
local wrapped = "local __ok, __err = xpcall(function()\n" .. source .. "\nend, function(e)\n" ..
	"  return tostring(e) .. '\nTRACESTART\n' .. debug.traceback()\nend)\n" ..
	"if not __ok then print('WRAPFAIL|' .. tostring(__err)) end\n"
local result = Sandbox.run(wrapped, { timeout = 180, maxExplored = 0 })
print("err:", result.err)
for _, entry in ipairs(result.outputs or {}) do print("OUT|" .. tostring(entry.text)) end
