local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")
local src = fs.readFile("../Samples/Luraph/luraph-v14.7.lua")
local r = Sandbox.run(src, {
  timeout = 30, allowHttp = false, maxExplored = 0, softInstanceCall = true,
})
print("err", tostring(r.err))
print("stages", #(r.stages or {}))
for i, st in ipairs(r.stages or {}) do
  local s = tostring(st.source or "")
  local posCount = select(2, s:gsub("Position", ""))
  local scpCount = select(2, s:gsub("SetControlPoints", ""))
  print(string.format("stage %d origin=%s len=%d Position=%d SCP=%d executed=%s",
    i, tostring(st.origin), #s, posCount, scpCount, tostring(st.executed)))
  if posCount > 0 then
    local idx = s:find("Position", 1, true)
    local a = math.max(1, idx - 60)
    local b = math.min(#s, idx + 40)
    print("  CTX:", s:sub(a, b):gsub("\n", " "))
  end
end

for _, rec in ipairs(r.trace.records) do
  if rec.kind == "loadstring" then
    local e = tostring(rec.expression or "")
    local posCount = select(2, e:gsub("Position", ""))
    if posCount > 0 then
      print("LOAD has Position x" .. posCount .. " len=" .. #e)
      local idx = e:find("Position", 1, true)
      print("  CTX:", e:sub(math.max(1, idx-80), math.min(#e, idx+40)):gsub("\n"," "))
    end
  end
end
