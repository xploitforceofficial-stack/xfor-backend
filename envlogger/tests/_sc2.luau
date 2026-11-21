local Sandbox = require("../src/core/sandbox")
local cases = {
  "local t = {} local c = __FUHD_SAFE_INDEX__(t, 'CurrentCamera') return tostring(c)",
  "local c = __FUHD_SAFE_INDEX__(nil, 'x') return tostring(c.Position)",
  "local c = __FUHD_SAFE_INDEX__(nil, 'x') local d = c.CFrame return tostring(d)",
  "local t = {} local c = __FUHD_SAFE_INDEX__(t, 'CurrentCamera') local d = c.CFrame return tostring(d)",
}
for i, src in ipairs(cases) do
  local r = Sandbox.run(src, {
    timeout = 3, maxNest = 2, traceLimit = 2000,
    onProgress = function() end, allowHttp = false,
    softInstanceCall = true, noInstrument = true,
  })
  print(i, "err=", tostring(r.err):sub(1, 120), "res=", tostring(r.results and r.results[1]))
end
