local fs = require("@lune/fs")
local SrcEdit = require("../src/core/srcedit")
local Instrument = require("../src/core/instrument")
local src = fs.readFile("../Samples/Luraph/luraph-v14.7.lua")

local n = 0
for _ in src:gmatch("Position") do n += 1 end
print("literal Position in source:", n)

local ok, w = pcall(SrcEdit.wrapSafeIndexing, src, Instrument.tokenize)
print("wrap ok:", ok, "len:", type(w)=="string" and #w or tostring(w))
if ok and type(w)=="string" then
  local m = 0
  for _ in w:gmatch("__FUHD_SAFE_INDEX__") do m += 1 end
  print("SAFE_INDEX count:", m)

  local i = w:find('"Position"', 1, true)
  if i then
    print("CTX:", w:sub(math.max(1,i-100), math.min(#w, i+50)):gsub("\n"," "))
  end
end
