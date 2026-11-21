local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local source = [====[
local out = {}
local function log(s) out[#out+1] = s end
local function safeTypeof(v) local ok, t = pcall(typeof or type, v) return ok and t or type(v) end
local function step(name, fn)
	local ok, err = pcall(fn)
	log(name .. ": " .. (ok and "OK" or "FAIL " .. tostring(err):sub(1, 120)))
end

step("setfenv-on-loadstring", function()
	local fn = loadstring("return foo")
	local env = { foo = 123 }
	setfenv(fn, env)
	assert(fn() == 123)
end)

step("utf8.graphemes", function()
	assert(type(utf8.graphemes) == "function")
	local n = 0
	for g in utf8.graphemes("héllo") do n += 1 end
	assert(n == 5, "got " .. n)
end)

step("math.nan", function()
	assert(math.nan ~= math.nan)
end)

step("Enum.AccessModifierType", function()
	assert(Enum.AccessModifierType ~= nil)
	assert(safeTypeof(Enum.AccessModifierType) == "Enum" or type(Enum.AccessModifierType) ~= "nil")
end)

step("Enum:GetEnums", function()
	local list = Enum:GetEnums()
	assert(type(list) == "table" and #list > 20, "n=" .. tostring(#list))
end)

step("tostring-rename", function()
	local p = Instance.new("Part")
	p.Name = "Alpha"
	local s1 = tostring(p)
	p.Name = "Beta"
	assert(tostring(p) ~= s1)
end)

step("BloomEffect.Intensity", function()
	local b = Instance.new("BloomEffect")
	assert(type(b.Intensity) == "number", "type=" .. type(b.Intensity))
end)

step("ForceField.Visible", function()
	local ff = Instance.new("ForceField")
	assert(type(ff.Visible) == "boolean", "type=" .. type(ff.Visible))
end)

step("HingeConstraint.ActuatorType", function()
	local hg = Instance.new("HingeConstraint")
	assert(safeTypeof(hg.ActuatorType) == "EnumItem", "type=" .. safeTypeof(hg.ActuatorType))
end)

step("TweenService-rejects-bad-goal", function()
	local ts = game:GetService("TweenService")
	local part = Instance.new("Part")
	local ok = pcall(function()
		ts:Create(part, TweenInfo.new(1), { Position = "bad" })
	end)
	assert(not ok, "should reject string goal")
end)

step("HttpService.GetSecret-invalid", function()
	local hs = game:GetService("HttpService")
	local ok = pcall(function()
		hs:GetSecret("eunc_invalid_key_zzz")
	end)
	assert(not ok, "should error on invalid key")
end)

step("EncodingService-Zstd", function()
	local es = game:GetService("EncodingService")
	local payload = "eUNC-zstd-roundtrip"
	local round
	if es.CompressZstd then
		round = es:DecompressZstd(es:CompressZstd(payload))
	elseif es.ZstdCompress then
		round = es:ZstdDecompress(es:ZstdCompress(payload))
	else
		local buf = buffer.fromstring(payload)
		local comp = es:CompressBuffer(buf, Enum.CompressionAlgorithm.Zstd)
		local de = es:DecompressBuffer(comp, Enum.CompressionAlgorithm.Zstd)
		round = buffer.tostring(de)
	end
	assert(round == payload, "round=" .. tostring(round))
end)

print(table.concat(out, "\n"))
]====]

local ok, res = pcall(Sandbox.run, source, { timeout = 60, maxNest = 1 })
if not ok then
	print("SANDBOX CRASH:", res)
	return
end
print("ok:", res.ok, "err:", tostring(res.err):sub(1, 300))
if type(res.outputs) == "table" then
	for _, item in res.outputs do
		print(if type(item) == "table" then tostring(item.text or item[1]) else tostring(item))
	end
end
