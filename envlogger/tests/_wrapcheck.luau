local Instrument = require("../src/core/instrument")
local SrcEdit = require("../src/core/srcedit")
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_mv_rob.lua")
print("chunk:", #src, "bytes")

local ok0 = pcall(luau.load, src, { debugName = "raw" })
print("raw compiles:", ok0)

local tokens = Instrument.tokenize(src)
print("tokens:", #tokens)

local wrapped, err = SrcEdit.wrapSafeIndexing(src, Instrument.tokenize)
print("wrapSafeIndexing ->", wrapped and #wrapped or "nil", err)

if wrapped then
	local ok, errC = pcall(luau.load, wrapped, { debugName = "wrapped" })
	print("wrapped compiles:", ok, errC)
	if not ok then

		local line, col = tostring(errC):match(":(%d+):?(%d*)")
		print("error at line:", line, col)
	end
end

local wrapped2, err2 = SrcEdit.wrapFunctions(src, Instrument.tokenize)
print("wrapFunctions ->", wrapped2 and #wrapped2 or "nil", err2)
if wrapped2 then
	local ok2, errC2 = pcall(luau.load, wrapped2, { debugName = "wrapped2" })
	print("wrapped2 compiles:", ok2, errC2)
end
