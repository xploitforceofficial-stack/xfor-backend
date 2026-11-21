local Sandbox = require("../src/core/sandbox")
local cases = {
  { name="A", src="local t = {} local c = __FUHD_SAFE_INDEX__(t, 'CurrentCamera') return tostring(c)" },
  { name="B", src="local c = __FUHD_SAFE_INDEX__(nil, 'x') return tostring(c.Position)" },
  { name="C", src="local c = __FUHD_SAFE_INDEX__(nil, 'x') local d = c.CFrame return tostring(d)" },
  { name="D", src="local t = {} local c = __FUHD_SAFE_INDEX__(t, 'CurrentCamera') local d = c.CFrame local e = __FUHD_SAFE_INDEX__(d, 'Position') return tostring(e)" },
}
for _, c in ipairs(cases) do
  local r = Sandbox.run(c.src, {
    timeout = 3, maxNest = 2, traceLimit = 2000,
    onProgress = function() end, allowHttp = false,
    softInstanceCall = true, noInstrument = true,
  })
  print(c.name, "err=", tostring(r.err):sub(1,120), "res=", tostring(r.results and r.results[1]))
end
