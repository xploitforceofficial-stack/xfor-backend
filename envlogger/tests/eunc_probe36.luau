local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local function run(label: string, code: string)
	local ok, res = pcall(Sandbox.run, code, { timeout = 30, maxNest = 1, name = "probe" })
	if not ok then
		print(label, "SANDBOX CRASH:", tostring(res):sub(1, 150))
		return
	end
	print("==", label, "| ok:", tostring(res.ok), "| err:", tostring(res.err):sub(1, 150))
	if type(res.outputs) == "table" then
		for _, item in res.outputs do
			local t = if type(item) == "table" then tostring(item.text or item[1]) else tostring(item)
			print("   out:", t)
		end
	end
end

run("tween-instance", [[
	local ts = game:GetService("TweenService")
	local part = Instance.new("Part")
	local tw = ts:Create(part, TweenInfo.new(0.1), {Transparency = 1})
	print("typeof:", typeof(tw))
	print("classname:", tostring(tw.ClassName))
]])

run("setfenv-after-instance", [[
	local p = Instance.new("Part")
	local fn = loadstring("return foo")
	local env = { foo = 123 }
	setfenv(fn, env)
	print("result:", tostring(fn()))
]])
