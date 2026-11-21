local fs = require("@lune/fs")
local SrcEdit = require("../src/core/srcedit")
local Instrument = require("../src/core/instrument")
local src = fs.readFile("tests/antitamper/at3_errors.lua")
local out, err = SrcEdit.wrapSafeIndexing(src, Instrument.tokenize)
print("err:", tostring(err))
if out then
	local fn, cerr = loadstring(out)
	print("compiles:", tostring(fn ~= nil), tostring(cerr))

	local lines = string.split(out, "\n")
	for i = 40, 48 do
		print(i, (lines[i] or ""):sub(1, 120))
	end
end
