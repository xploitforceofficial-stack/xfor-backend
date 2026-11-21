local luauL = require("@lune/luau")
local Instrument = require("../src/core/instrument")
local SrcEdit = require("../src/core/srcedit")
local fs = require("@lune/fs")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_mv_rob.lua")

local function applyFirstN(srcText: string, edits: { any }, n: number): string
	local sorted = table.clone(edits)
	table.sort(sorted, function(a, b)
		if a.start == b.start then return a.finish < b.finish end
		return a.start < b.start
	end)
	local taken = {}
	for i = 1, math.min(n, #sorted) do taken[i] = sorted[i] end
	return SrcEdit.apply(srcText, taken)
end

local toks = Instrument.tokenize(src)
toks.src = src

local full = SrcEdit.wrapSafeIndexing(src, Instrument.tokenize)
local wrappedAll = full

local positions = {}
local cursor = 1
while true do
	local s, e = string.find(wrappedAll, "__FUHD_SAFE_INDEX__%b()", cursor)
	if not s then break end
	local after = string.sub(wrappedAll, e + 1, e + 1)
	if after ~= "" and not after:match("[%s%+%-%*/%%%^#<>=~%(,;%)%]}%.:{andoril]") and after ~= "." then
		positions[#positions+1] = { s = s, e = e, after = after }
	end
	cursor = e + 1
end
print("suspicious sites:", #positions)
for i, p in ipairs(positions) do
	if i > 8 then break end
	print(i, "after=" .. string.format("%q", p.after), string.format("%q", string.sub(wrappedAll, p.e - 10, p.e + 20)))
end
