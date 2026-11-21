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

run("enc-unknown", [[
	local es = game:GetService("EncodingService")
	print("ClassName:", es.ClassName)
	-- walk known members that DO exist:
	print("Decompress:", typeof(es.Decompress))
	-- now check exactly what CompressZstd resolves to:
	local v = es.CompressZstd
	print("path hint:", tostring(v):sub(1, 70))
]])
