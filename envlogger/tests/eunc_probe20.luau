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

run("enum-raw", [[
	-- what does the metatable of Enum look like from inside?
	local e = Enum
	local mt = getmetatable(e)
	print("mt is locked string:", tostring(mt))
	-- try direct category + then GetEnums
	print("cat:", tostring(Enum.AccessModifierType ~= nil))
	-- what other names exist?
	print("tp of Enum:", typeof(e))
]])
