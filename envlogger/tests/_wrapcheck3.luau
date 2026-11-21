local Instrument = require("../src/core/instrument")
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_mv_rob.lua")

local lo, hi = 1, #src
local function wrapsBad(len: number): boolean
	local slice = string.sub(src, 1, len)

	local wrapped, err = SrcEditWrap(slice)
	if not wrapped then return false end
	local ok = pcall(luau.load, wrapped, { debugName = "s" })
	return not ok
end
