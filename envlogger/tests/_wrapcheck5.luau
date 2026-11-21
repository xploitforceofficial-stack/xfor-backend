local Instrument = require("../src/core/instrument")
local SrcEdit = require("../src/core/srcedit")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_mv_rob.lua")
local wrapped2, err2 = SrcEdit.wrapFunctions(src, Instrument.tokenize)
print("wrapFunctions ->", wrapped2 and #wrapped2 or "nil", err2)
if wrapped2 then
	local ok2 = pcall(luau.load, wrapped2, { debugName = "w2" })
	print("compiles:", ok2)
end
local w, e = SrcEdit.wrapSafeIndexing(src, Instrument.tokenize)
print("safeIndex ->", w and #w or "nil", e)
if w then
	local ok3 = pcall(luau.load, w, { debugName = "w3" })
	print("compiles:", ok3)
end
