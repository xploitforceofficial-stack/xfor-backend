local fs = require("@lune/fs")
local Instrument = require("../src/core/instrument")
local SrcEdit = require("../src/core/srcedit")

local source = fs.readFile("../Samples/Moonveli/v2.0.23/1.lua")

local i = source:find("k=function", 1, true)
local slice = source:sub(i - 8, i + 12)
print("context around k=function:", slice)

local okTok, toks = pcall(Instrument.tokenize, source:sub(1, 300))
if okTok then
	for idx = 1, math.min(#toks, 24) do
		print(idx, toks[idx].kind, toks[idx].raw)
	end
end
