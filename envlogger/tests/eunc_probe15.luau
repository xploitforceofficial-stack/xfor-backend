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

run("setfenv-ls", [[
	local fn = loadstring("return foo")
	local env = { foo = 123 }
	setfenv(fn, env)
	print("result:", tostring(fn()))
]])

run("isnan", [[
	print("isnan:", type(math.isnan))
]])

run("enum-count", [[
	local list = Enum:GetEnums()
	print("count:", #list)
]])

run("zstd-buf", [[
	local es = game:GetService("EncodingService")
	local payload = "eUNC-zstd-roundtrip"
	local buf = buffer.fromstring(payload)
	local ok, comp = pcall(function() return es:CompressBuffer(buf, Enum.CompressionAlgorithm.Zstd) end)
	print("compress:", tostring(ok), tostring(comp))
	local ok2, de = pcall(function() return es:DecompressBuffer(comp, Enum.CompressionAlgorithm.Zstd) end)
	print("decompress:", tostring(ok2), tostring(de))
	if ok2 then print("round:", tostring(buffer.tostring(de))) end
]])
