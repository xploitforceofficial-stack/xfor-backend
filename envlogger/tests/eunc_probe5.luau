local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local source = [====[
local out = {}
local function log(s) out[#out+1] = s end
local function safeTypeof(v) local ok, t = pcall(typeof or type, v) return ok and t or type(v) end

-- setfenv on loadstring function
local okS, errS = pcall(function()
	local fn = loadstring("return foo")
	local env = { foo = 123 }
	setfenv(fn, env)
	assert(fn() == 123, "got " .. tostring(fn()))
end)
log("setfenv loadstring: " .. tostring(okS) .. " " .. tostring(errS))

-- utf8.graphemes
log("type utf8.graphemes: " .. type(utf8.graphemes))
local okG, resG = pcall(function()
	local n = 0
	for g in utf8.graphemes("héllo") do n += 1 end
	return n
end)
log("graphemes count: " .. tostring(resG) .. " ok: " .. tostring(okG))

-- math.nan exists?
log("math.nan: " .. tostring(math.nan))

-- Enum.AccessModifierType
log("Enum.AccessModifierType: " .. tostring(Enum.AccessModifierType))
log("typeof: " .. safeTypeof(Enum.AccessModifierType))

-- Enum:GetEnums
local list = Enum:GetEnums()
log("GetEnums n: " .. tostring(#list))

-- tostring rename
local p = Instance.new("Part")
p.Name = "Alpha"
local s1 = tostring(p)
p.Name = "Beta"
local s2 = tostring(p)
log("tostring s1: " .. s1)
log("tostring s2: " .. s2)
log("s1 ~= s2: " .. tostring(s1 ~= s2))

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
