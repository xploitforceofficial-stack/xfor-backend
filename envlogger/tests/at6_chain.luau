local SrcEdit = require("../src/core/srcedit")
local Instrument = require("../src/core/instrument")

local src = [[
local p = Instance.new("Part")
local h = game:GetService("CollectionService"):HasTag(p, "tag")
local t = string.format("%s", tostring(h))
game:GetService("TextService"):GetTextSize("test", 16, Enum.Font.Unknown, Vector2.new(100, 100))
]]

local function report(label: string, text: string?)
	if text == nil then
		print(label, "SKIPPED")
		return
	end
	local fn, err = loadstring(text)
	print(label, fn and "compiles" or ("FAIL " .. tostring(err):sub(1, 200)))
end

local lowered = Instrument.lowerBitwise(src)
report("lowerBitwise", lowered)
local base = lowered or src

local transformed = Instrument.apply(base, { operators = true })
report("Instrument.apply(ops)", transformed)
report("Instrument.apply(noops)", Instrument.apply(base, { operators = false }))
report("applyLoops", Instrument.applyLoops(base))
report("wrapFunctions", SrcEdit.wrapFunctions(base, Instrument.tokenize))
report("wrapSafeIndexing", select(1, SrcEdit.wrapSafeIndexing(base, Instrument.tokenize)))
