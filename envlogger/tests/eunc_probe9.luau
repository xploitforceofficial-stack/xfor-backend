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

step("Part.Transparency-Shape", function()
	local p = Instance.new("Part")
	assert(type(p.Transparency) == "number", "transparency type=" .. type(p.Transparency))
	assert(p.Shape ~= nil, "shape nil")
end)

step("Part defaults values", function()
	local p = Instance.new("Part")
	log("  Part.Transparency=" .. tostring(p.Transparency))
	log("  Part.Anchored=" .. tostring(p.Anchored))
	log("  Part.CanCollide=" .. tostring(p.CanCollide))
	log("  Part.Name=" .. tostring(p.Name))
	log("  typeof Part.Material=" .. safeTypeof(p.Material))
	log("  Part.Shape=" .. tostring(p.Shape))
end)

step("TextLabel.TextTruncate", function()
	local tl = Instance.new("TextLabel")
	log("  typeof=" .. safeTypeof(tl.TextTruncate))
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
