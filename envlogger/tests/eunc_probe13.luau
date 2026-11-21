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

run("tween-badgoal", [[
	local ts = game:GetService("TweenService")
	local part = Instance.new("Part")
	local ok = pcall(function()
		return ts:Create(part, TweenInfo.new(1), {Position = "bad"})
	end)
	print("bad-ok:", tostring(ok))
]])

run("hinge-actuator", [[
	local hg = Instance.new("HingeConstraint")
	print("tp:", typeof(hg.ActuatorType))
	print("val:", tostring(hg.ActuatorType))
]])

run("getsecret-invalid", [[
	local hs = game:GetService("HttpService")
	local ok = pcall(function() return hs:GetSecret("eunc_invalid_key_zzz") end)
	print("ok:", tostring(ok))
]])

run("zstd", [[
	local es = game:GetService("EncodingService")
	print("CompressZstd:", tostring(es.CompressZstd))
	print("ZstdCompress:", tostring(es.ZstdCompress))
]])

run("enum-accessmod", [[
	print("am:", tostring(Enum.AccessModifierType))
]])

run("nan-expr", [[
	local nan = 0 / 0
	print("neq:", tostring(nan ~= nan))
]])
