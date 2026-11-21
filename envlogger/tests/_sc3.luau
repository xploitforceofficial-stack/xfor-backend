local Sandbox = require("../src/core/sandbox")
local src = [[
local t = {}
local c = __FUHD_SAFE_INDEX__(t, "CurrentCamera")
local d = c.CFrame
local e = __FUHD_SAFE_INDEX__(d, "Position")
return type(c) .. "|" .. type(d) .. "|" .. type(e)
]]
for _, inst in ipairs({true, false}) do
  local r = Sandbox.run(src, {
    timeout = 3, maxNest = 2, traceLimit = 2000,
    onProgress = function() end, allowHttp = false,
    softInstanceCall = true, noInstrument = not inst,
  })
  print("instrument="..tostring(inst), "err=", tostring(r.err):sub(1,150), "res=", tostring(r.results and r.results[1]))
end
