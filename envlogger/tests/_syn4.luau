local luau = require("@lune/luau")
local Instrument = require("../src/core/instrument")
local SrcEdit = require("../src/core/srcedit")
local fs = require("@lune/fs")
local luauL = require("@lune/luau")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_mv_rob.lua")
local w = SrcEdit.wrapSafeIndexing(src, Instrument.tokenize)

local ok, err = pcall(luauL.load, w, { debugName = "w" })
local line = tostring(err):match(":(%d+):")
print("err line:", line, "->", tostring(err):match("Expected [^\n]*"))

local lines = {}
for l in (w .. "\n"):gmatch("(.-)\n") do lines[#lines+1] = l end
print("total lines:", #lines)
if line then
	local ln = tonumber(line)
	local text = lines[ln] or ""
	print("line len:", #text)

	local col = tostring(err):match(":(%d+):(%d+)")
	print("col:", col)
	local c = tonumber(col) or 1
	print("CTX:", string.format("%q", text:sub(math.max(1, c-80), c+80)))
end
