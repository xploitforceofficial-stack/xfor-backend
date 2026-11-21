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

run("nan-line", [[
	local r = {}
	local ok, err = pcall(function() return math.isnan end)
	print("isnan-index:", tostring(ok), tostring(err))
	local nan = 0/0
	print("neq:", tostring(nan ~= nan))
]])

run("graphemes", [[
	print("gtype:", type(utf8.graphemes))
	print("call:", type(utf8.graphemes("héllo")))
]])

run("enc-props", [[
	local es = game:GetService("EncodingService")
	print("has-CZ:", tostring(es.CompressZstd ~= nil))
	print("has-ZC:", tostring(es.ZstdCompress ~= nil))
	print("has-C:", tostring(es.Compress ~= nil))
	local ok, r = pcall(function() return es:Compress("x") end)
	print("compress:", tostring(ok), tostring(r))
]])

run("enum-tp", [[
	print("am-tp:", typeof(Enum.AccessModifierType))
	print("am-cls:", tostring(Enum.AccessModifierType.Name))
]])
