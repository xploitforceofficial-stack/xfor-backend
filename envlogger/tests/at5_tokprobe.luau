local Instrument = require("../src/core/instrument")
local SrcEdit = require("../src/core/srcedit")

local src = "local s = { x = workspace }\nlocal k2, v2 = next(s, nil)\nprint(\"spyval:\", k2, v2, type(v2))\n"

local toks = Instrument.tokenize(src)
for i, t in ipairs(toks) do
	if i <= 40 then
		print(i, t.kind, string.format("%q", t.raw), t.start)
	end
end

local loops = Instrument.applyLoops(src)
print("---applyLoops:")
print(loops)
print("---wrapSafeIndexing:")
local safe = SrcEdit.wrapSafeIndexing(src, Instrument.tokenize)
print(safe)
