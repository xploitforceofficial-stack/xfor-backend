local Sandbox = require("../src/core/sandbox")
local src = [[
local n = nil
local s = __FUHD_SAFE__(n)
local a = s.Position
local b = __FUHD_SAFE_INDEX__(n, "Position")
local c = n.Position
return tostring(a) .. "|" .. tostring(b)
]]
local r = Sandbox.run(src, {
  timeout = 5, maxNest = 2, traceLimit = 10000,
  onProgress = function() end, allowHttp = false,
  softInstanceCall = true,
})
print("err=", tostring(r.err))
print("results=", tostring(r.results and r.results[1]))
