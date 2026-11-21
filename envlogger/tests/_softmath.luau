local Sandbox = require("../src/core/sandbox")
local src = [[
local n = nil
local s = __FUHD_SAFE__(n)
local x = s.Position
local y = x + 1
local z = tostring(s) .. tostring(x)
return z .. ":" .. tostring(y)
]]
local r = Sandbox.run(src, {
  timeout = 5, maxNest = 2, traceLimit = 5000,
  onProgress = function() end, allowHttp = false,
  softInstanceCall = true,
})
print("err=", tostring(r.err), "res=", tostring(r.results and r.results[1]))
