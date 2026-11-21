local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")
local src = fs.readFile("../Samples/Luraph/luraph-v14.7.lua")
local r = Sandbox.run(src, { timeout = 60, allowHttp = false, maxExplored = 0, noInstrument = true })
print("err", tostring(r.err))

local n = 0
for k, v in pairs(r.stringTable or {}) do
  local s = tostring(v)
  if s:find("Position", 1, true) or s:find("SetControlPoints", 1, true) or s:find("Humanoid", 1, true) or s:find("Character", 1, true) then
    print("ST:", tostring(k):sub(1,40), "=", s:sub(1,120))
    n += 1
    if n > 30 then break end
  end
end
print("matches", n)

n = 0
for _, rec in ipairs(r.vmTrace or {}) do
  local s = tostring(rec)
  if s:find("Position", 1, true) or s:find("SetControlPoints", 1, true) then
    print("VT:", s:sub(1, 150))
    n += 1
    if n > 20 then break end
  end
end
print("vm matches", n)
