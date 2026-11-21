local Instrument = require("../src/core/instrument")
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_mv_rob.lua")
local tokens = Instrument.tokenize(src)
print("tokens:", #tokens)

local SrcEdit = require("../src/core/srcedit")
local wrapped = SrcEdit.wrapFunctions(src, Instrument.tokenize)
print("wrapped len:", #wrapped, "src len:", #src)

local n = math.min(#src, #wrapped)
local diffAt = nil
for i = 1, n do
	local a = string.byte(src, i)
	local b = string.byte(wrapped, i)
	if a ~= b then
		diffAt = i
		break
	end
end
if diffAt then
	print("first diff at byte:", diffAt)
	print("src   ...", string.format("%q", string.sub(src, math.max(1, diffAt-60), diffAt+60)))
	print("wrapd ...", string.format("%q", string.sub(wrapped, math.max(1, diffAt-60), diffAt+60)))
else
	print("wrapped is a prefix-identical expansion")
end
