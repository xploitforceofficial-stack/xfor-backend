local fs = require("@lune/fs")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_mv_rob.lua")

print(string.format("RAW: %q", string.sub(src, 4240, 4420)))

local Instrument = require("../src/core/instrument")
local SrcEdit = require("../src/core/srcedit")
local w = SrcEdit.wrapSafeIndexing(src, Instrument.tokenize)
print(string.format("WRP: %q", string.sub(w, 4240, 4440)))
