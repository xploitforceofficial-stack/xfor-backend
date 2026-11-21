local Instrument = require("../src/core/instrument")
local SrcEdit = require("../src/core/srcedit")
local fs = require("@lune/fs")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_mv_rob.lua")
local w = SrcEdit.wrapSafeIndexing(src, Instrument.tokenize)
local wrapped = w
local n = math.min(#src, #wrapped)
local diffAt = nil
for i = 1, n do
	if string.byte(src, i) ~= string.byte(wrapped, i) then
		diffAt = i
		break
	end
end
if diffAt then
	print("first diff at byte:", diffAt)
	print("src   ...", string.format("%q", string.sub(src, math.max(1, diffAt-70), diffAt+70)))
	print("wrapd ...", string.format("%q", string.sub(wrapped, math.max(1, diffAt-70), diffAt+90)))
else
	print("prefix-identical")
end
