local Instrument = require("../src/core/instrument")
local SrcEdit = require("../src/core/srcedit")
local fs = require("@lune/fs")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_mv_rob.lua")
local full = SrcEdit.wrapSafeIndexing(src, Instrument.tokenize)
local edits = SrcEdit._lastSafeEdits
print("edits:", #edits)

local idx
for i, e in ipairs(edits) do
	if e.start == 142620 then idx = i break end
end
print("edit idx:", idx)
local toks = Instrument.tokenize(src)

for i, t in ipairs(toks) do
	if t.start == 142620 then
		for k = math.max(1, i-2), math.min(#toks, i+12) do
			print(k, toks[k].kind, string.format("%q", string.sub(src, toks[k].start, toks[k].start + #toks[k].raw - 1)))
		end
		break
	end
end

for i, t in ipairs(toks) do
	if t.start == 142620 then
		for k = i, math.min(#toks, i + 20) do
			if toks[k].raw == "=" then print("found = at tok", k, "raw:", toks[k].raw) break end
		end
		break
	end
end
