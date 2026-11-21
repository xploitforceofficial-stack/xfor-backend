local fs = require("@lune/fs")
local Instrument = require("../src/core/instrument")
local src = fs.readFile("../Samples/Luraph/luraph-v14.7.lua")
local t = Instrument.apply(src, { operators = true })
if type(t) == "string" then
  local n = 0
  for _ in t:gmatch("Position") do n += 1 end
  print("instrumented Position count:", n, "len", #t)
  local i = t:find("Position", 1, true)
  if i then print("CTX:", t:sub(math.max(1,i-80), math.min(#t,i+40)):gsub("\n"," ")) end
else
  print("instrument apply failed", t)
  local t2 = Instrument.apply(src, { operators = false })
  if type(t2)=="string" then
    local n = 0
    for _ in t2:gmatch("Position") do n += 1 end
    print("noops Position count:", n)
    local i = t2:find("Position", 1, true)
    if i then print("CTX:", t2:sub(math.max(1,i-80), math.min(#t2,i+40)):gsub("\n"," ")) end
  end
end
