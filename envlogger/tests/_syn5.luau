local luauL = require("@lune/luau")
local Instrument = require("../src/core/instrument")
local SrcEdit = require("../src/core/srcedit")
local fs = require("@lune/fs")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_mv_rob.lua")
local w = SrcEdit.wrapSafeIndexing(src, Instrument.tokenize)

local toks = Instrument.tokenize(src)
toks.src = src
local edits = nil

local spread = w:gsub("%f[%w_]", "\n")
print("trying spread-off")

local ok, err = pcall(luauL.load, w, { debugName = "w" })
print(tostring(err))
