local Sandbox = require("../src/core/sandbox")

local src = [[
local function f11(callback)
	local function layer4() local a, b = callback() return a, b end
	local function layer3() local a, b = layer4() return a, b end
	local function layer2() local a, b = layer3() return a, b end
	local function layer1() local a, b = layer2() return a, b end
	return layer1()
end

local t13 = {}
local ok, err = f11(function()
	return xpcall(function()
		return (getfenv)(-1)
	end, function(err2)
		for _, level in ipairs({ 5, 6, 7, 8, 10, 11 }) do
			local okL, value = pcall(function() return debug.info(level, "f") end)
			print("probe", level, tostring(okL), tostring(value))
			t13[level] = (okL and value) or nil
		end
		return err2
	end)
end)
for _, level in ipairs({ 5, 6, 7, 8, 10, 11 }) do
	print("level", level, tostring(t13[level] == nil and "NIL" or "nonnil"))
end
]]

local ok, res = pcall(Sandbox.run, src, { timeout = 30 })
if not ok then
	print("sandbox error:", res)
	return
end
print("ok:", res.ok, "err:", res.err)
for _, entry in ipairs(res.outputs or {}) do
	print("OUT|" .. tostring(entry.text))
end
