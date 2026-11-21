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

run("enum-getenums", [[
	local _ = Enum.AccessModifierType
	local list = Enum:GetEnums()
	print("count:", #list)
	print("first:", tostring(list[1]))
]])

run("hinge2", [[
	local h = Instance.new("HingeConstraint")
	local v = h.ActuatorType
	print("tp:", typeof(v), "val:", tostring(v))
]])
