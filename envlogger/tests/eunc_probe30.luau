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

run("enc-trace", [[
	local es = game:GetService("EncodingService")
	print("CZ typeof:", typeof(es.CompressZstd))
	local ok, res = pcall(es.CompressZstd, es, "hello")
	print("call:", tostring(ok))
	print("res type:", type(res))
	print("res:", tostring(res):sub(1, 80))
]])
