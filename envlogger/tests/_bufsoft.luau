local Sandbox = require("../src/core/sandbox")
local src = [[
local b = buffer.create(16)
local soft = __FUHD_SAFE_INDEX__(nil, "x")
-- if soft is softNil table, writeu32 should coerce
local ok, err = pcall(function()
  buffer.writeu32(b, 0, soft)
end)
local ok2, err2 = pcall(function()
  buffer.writeu32(b, 4, 42)
end)
return tostring(ok) .. "|" .. tostring(err) .. "|" .. tostring(ok2)
]]
local r = Sandbox.run(src, {
  timeout = 5, maxNest = 2, traceLimit = 5000,
  onProgress = function() end, allowHttp = false,
  softInstanceCall = true, noInstrument = true,
})
print("err=", tostring(r.err), "res=", tostring(r.results and r.results[1]))
