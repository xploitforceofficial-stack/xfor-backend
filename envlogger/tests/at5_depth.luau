local Sandbox = require("../src/core/sandbox")
local function make(body)
	return string.format([[
local function f11(cb)
	local function layer4() local a,b = cb() return a,b end
	local function layer3() local a,b = layer4() return a,b end
	local function layer2() local a,b = layer3() return a,b end
	local function layer1() local a,b = layer2() return a,b end
	return layer1()
end
local ok, err = f11(function()
	return xpcall(function()
		local _ = %s
	end, function(e)
		for i = 1, 18 do
			local okI, v = pcall(debug.info, i, "f")
			local okSl, ln = pcall(function() return debug.info(i, "l") end)
			local okS, s = pcall(function() return debug.info(i, "s") end)
			print("d", i, "f=" .. tostring(okI and (v == nil and "NIL" or "FN") or "ERR"), "s=" .. tostring(okS and tostring(s) or "ERR"), "l=" .. tostring(okSl and tostring(ln) or "?"))
		end
		return e
	end)
end)
]], body)
end

for _, case in ipairs({ { "err", 'error("boom")' }, { "getfenv", '(getfenv)(-1)' }, { "char", 'string.char(nil)' } }) do
	print("===== case " .. case[1])
	local ok, res = pcall(Sandbox.run, make(case[2]), { timeout = 30 })
	if not ok then print("sandbox error:", res) else
		for _, e in ipairs(res.outputs or {}) do print("OUT|" .. tostring(e.text)) end
	end
end
