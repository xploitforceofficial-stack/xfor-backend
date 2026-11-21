local Sandbox = require("../src/core/sandbox")

local cases = {
  { name="bracket dynamic", src='local t = nil local k = "Position" return t[k]' },
  { name="bracket wrapped", src='local t = nil local k = "Position" return __FUHD_SAFE_INDEX__(t, k)' },
  { name="dot", src='local t = nil return t.Position' },
  { name="computed chain", src='local a = {} local b = a[nil] return b.Position' },
}
for _, c in ipairs(cases) do
  local r = Sandbox.run(c.src, {
    timeout = 5, maxNest = 2, traceLimit = 10000,
    onProgress = function() end, allowHttp = false,
    softInstanceCall = true,
    noInstrument = true,
  })
  print(c.name, "err=", tostring(r.err))
end
