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

run("enc-methods", [[
	local es = game:GetService("EncodingService")
	print("CZ type:", type(es.CompressZstd))
	print("ZC type:", type(es.ZstdCompress))
	print("CB type:", type(es.CompressBuffer))
	print("DB type:", type(es.DecompressBuffer))
	local ok, err = pcall(function()
		local buf = buffer.fromstring("eUNC-zstd-roundtrip")
		local comp = es:CompressBuffer(buf, Enum.CompressionAlgorithm.Zstd)
		local de = es:DecompressBuffer(comp, Enum.CompressionAlgorithm.Zstd)
		print("round==:", buffer.tostring(de) == "eUNC-zstd-roundtrip")
	end)
	print("path-ok:", tostring(ok), tostring(err))
]])
