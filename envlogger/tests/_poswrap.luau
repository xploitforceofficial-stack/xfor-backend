local fs = require("@lune/fs")
local SrcEdit = require("../src/core/srcedit")
local Instrument = require("../src/core/instrument")
local src = fs.readFile("../Samples/Luraph/luraph-v14.7.lua")
local w, e = SrcEdit.wrapSafeIndexing(src, Instrument.tokenize)
if not w then print("wrap fail", e); return end
print("wrapped len", #w)

local count = 0
local pos = 1
while true do
  local s = string.find(w, ".Position", pos, true)
  if not s then break end
  count += 1
  if count <= 30 then
    local ctx = string.sub(w, math.max(1, s-60), math.min(#w, s+40))
    ctx = ctx:gsub("\n", " ")
    print(count, ctx)
  end
  pos = s + 1
end
print("total .Position occurrences:", count)

local safePos = 0
for _ in string.gmatch(w, '__FUHD_SAFE_INDEX__%b()[,%s]*"Position"') do safePos += 1 end
print("SAFE_INDEX Position pattern:", safePos)

local n = 0
for _ in string.gmatch(w, '%__FUHD_SAFE_INDEX__') do n += 1 end
print("total SAFE_INDEX:", n)
