local fs = require("@lune/fs")
local SrcEdit = require("../src/core/srcedit")
local Instrument = require("../src/core/instrument")
local src = fs.readFile("tests/antitamper/at3_errors.lua")
local out = SrcEdit.wrapSafeIndexing(src, Instrument.tokenize)
local ok, fn = pcall(loadstring, out)
print("compiles:", tostring(ok))
local lines = string.split(out, "\n")
local srcLines = string.split(src, "\n")
for i = 40, 47 do
	print("OUT " .. i .. ": " .. (lines[i] or ""))
	print("SRC " .. i .. ": " .. (srcLines[i] or ""))
end
