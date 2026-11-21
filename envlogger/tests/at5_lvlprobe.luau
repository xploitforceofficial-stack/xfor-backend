local Sandbox = require("../src/core/sandbox")
local src = [[
local function f11(cb)
	local function layer4() local a,b = cb() return a,b end
	local function layer3() local a,b = layer4() return a,b end
	local function layer2() local a,b = layer3() return a,b end
	local function layer1() local a,b = layer2() return a,b end
	return layer1()
end
local ok, err = f11(function()
	return xpcall(function() error("boom") end, function(e)
		for i = 1, 14 do
			local okI, v = pcall(debug.info, i, "f")
			local okS, s = pcall(debug.info, i, "s")
			local okN, n = pcall(debug.info, i, "n")
			print("lvl", i, "f=", tostring(okI and (v == nil and "NIL" or (typeof and typeof(v) or type(v))) or "ERR"), "s=", tostring(okS and tostring(s) or "ERR"), "n=", tostring(okN and tostring(n) or "ERR"))
		end
		return e
	end)
end)
]]
local ok, res = pcall(Sandbox.run, src, { timeout = 30 })
if not ok then print("sandbox error:", res) return end
print("ok:", res.ok, "err:", res.err)
for _, e in ipairs(res.outputs or {}) do print("OUT|" .. tostring(e.text)) end
