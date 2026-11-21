local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local ok, res = pcall(Sandbox.run, [[
	local a = game.ServiceAdded:Connect(function() end)
	local b = game.ServiceAdded:Connect(function() end)
	a:Disconnect()
	b:Disconnect()
	local fn = loadstring("return foo")
	local env = { foo = 123 }
	setfenv(fn, env)
	print("setfenv result:", fn() == 123)
	print("graphemes fn:", type(utf8.graphemes) == "function")
	print("isnan:", math.isnan == nil or type(math.isnan) == "function" or math.isnan(0/0))
	local nan = 0/0
	print("nan neq:", nan ~= nan)
]], { timeout = 30, maxNest = 1, name = "probe" })
print("ok:", tostring(ok))
if type(res) == "table" then
	print("res.ok:", tostring(res.ok), "| err:", tostring(res.err):sub(1, 200))
	if type(res.outputs) == "table" then
		for _, item in res.outputs do
			local t = if type(item) == "table" then tostring(item.text or item[1]) else tostring(item)
			print("   out:", t)
		end
	end
end
