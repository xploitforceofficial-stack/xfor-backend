local fs = require("@lune/fs")
local SrcEdit = require("../src/core/srcedit")
local Instrument = require("../src/core/instrument")
local src = fs.readFile("../Samples/Luraph/luraph-v14.7.lua")
local w = SrcEdit.wrapSafeIndexing(src, Instrument.tokenize)

local rawDot, safeDot = 0, 0
for cap in w:gmatch("()%.Position") do

  local before = w:sub(math.max(1, cap-40), cap)
  if before:find("__FUHD_SAFE_INDEX__", 1, true) then safeDot += 1 else rawDot += 1; if rawDot <= 3 then print("RAW DOT CTX:", before .. ".Position") end end
end
print("raw .Position:", rawDot, "safe-wrapped:", safeDot)

local br = 0
for _ in w:gmatch('%[%s*"Position"%s*%]') do br += 1 end
print('["Position"] count:', br)
