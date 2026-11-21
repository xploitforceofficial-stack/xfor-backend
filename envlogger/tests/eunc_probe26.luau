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

run("tween-goal", [[
	local ts = game:GetService("TweenService")
	local part = Instance.new("Part")
	local ok = pcall(function()
		return ts:Create(part, TweenInfo.new(1), {Position = "bad"})
	end)
	print("bad-ok:", tostring(ok))
	local ok2 = pcall(function()
		return ts:Create(part, TweenInfo.new(1), {Transparency = 1})
	end)
	print("good-ok:", tostring(ok2))
	local ok3 = pcall(function()
		return ts:Create(part, TweenInfo.new(1), {Anchored = true})
	end)
	print("bool-ok:", tostring(ok3))
]])
