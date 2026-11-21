local luauL = require("@lune/luau")
local Instrument = require("../src/core/instrument")
local SrcEdit = require("../src/core/srcedit")
local fs = require("@lune/fs")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_mv_rob.lua")
local full = SrcEdit.wrapSafeIndexing(src, Instrument.tokenize)
local edits = SrcEdit._lastSafeEdits
print("total edits:", #edits)

local function compiles(text: string): boolean
	local ok = pcall(luauL.load, text, { debugName = "b" })
	return ok
end
print("all:", compiles(full))
local lo, hi = 1, #edits

table.sort(edits, function(a, b)
	if a.start == b.start then return a.finish < b.finish end
	return a.start < b.start
end)
local function breaks(n: number): boolean
	local taken = {}
	for i = 1, n do taken[i] = edits[i] end
	local text = SrcEdit.apply(src, taken)
	return not compiles(text)
end
if not breaks(#edits) then print("NOT BROKEN by edits?") return end
while lo < hi do
	local mid = math.floor((lo + hi) / 2)
	if breaks(mid) then hi = mid else lo = mid + 1 end
end
print("first breaking edit index:", lo)
local e = edits[lo]
print("edit:", e.start, e.finish, string.format("%q", e.text))
print("src ctx:", string.format("%q", string.sub(src, e.start - 60, e.finish + 60)))

local taken = {}
for i = 1, #edits do if i ~= lo then taken[#taken+1] = edits[i] end end
print("without this edit compiles:", compiles(SrcEdit.apply(src, taken)))
