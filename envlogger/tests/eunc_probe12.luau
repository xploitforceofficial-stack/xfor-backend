local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local function run(label: string, code: string)
	local ok, res = pcall(Sandbox.run, code, { timeout = 30, maxNest = 1, name = "probe" })
	if not ok then
		print(label, "SANDBOX CRASH:", tostring(res):sub(1, 120))
		return
	end
	print("==", label, "| ok:", tostring(res.ok), "| err:", tostring(res.err):sub(1, 120))
	if type(res.outputs) == "table" then
		for _, item in res.outputs do
			local t = if type(item) == "table" then tostring(item.text or item[1]) else tostring(item)
			print("   out:", t)
		end
	end
end

run("hb-after-write", [[
	local rs = game:GetService("RunService")
	print("before:", typeof(rs.Heartbeat))
	local ok = pcall(function() rs.Heartbeat = nil end)
	print("write-ok:", tostring(ok))
	print("after:", typeof(rs.Heartbeat))
]])

run("math-tointeger", [[
	print("tointeger:", tostring(math.tointeger))
	print("nan:", tostring(0/0 == 0/0))
]])

run("utf8-graphemes", [[
	print("graphemes:", tostring(utf8.graphemes))
]])
