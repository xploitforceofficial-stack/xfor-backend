local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local function run(label: string, code: string)
	local ok, res = pcall(Sandbox.run, code, { timeout = 30, maxNest = 1, name = "probe" })
	if not ok then
		print(label, "| ok:", tostring(res.ok), "| err:", tostring(res.err):sub(1, 150))
		if type(res.outputs) == "table" then
			for _, item in res.outputs do
				local t = if type(item) == "table" then tostring(item.text or item[1]) else tostring(item)
				print("   out:", t)
			end
		end
		return
	end
	print(label, "CRASH:", tostring(res))
end

run("pollution", [[
	-- step 1: ServiceAdded connects
	local a = game.ServiceAdded:Connect(function() end)
	local b = game.ServiceAdded:Connect(function() end)
	a:Disconnect()
	b:Disconnect()
	-- step 2: setfenv on loadstring
	local fn = loadstring("return foo")
	local env = { foo = 123 }
	setfenv(fn, env)
	print("setfenv result:", fn() == 123)
	-- step 3: nan/graphemes
	print("graphemes fn:", type(utf8.graphemes) == "function")
	print("isnan:", math.isnan == nil or type(math.isnan) == "function" or math.isnan(0/0))
	local nan = 0/0
	print("nan neq:", nan ~= nan)
]])
