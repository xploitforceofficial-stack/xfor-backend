local Instrument = require("../src/core/instrument")
local SrcEdit = require("../src/core/srcedit")
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_mv_rob.lua")

local tokens = Instrument.tokenize(src)
local i = 1
while i <= #tokens do
	local t = tokens[i]
	local tc = t.start
	if tc and tc >= 145250 and tc <= 145380 then
		print("tok", i, "start", tc, t.kind, string.format("%q", string.sub(src, tc, math.min(tc + 30, #src))))
	end
	if tc and tc > 145400 then break end
	i += 1
end
