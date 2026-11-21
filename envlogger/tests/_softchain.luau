local Sandbox = require("../src/core/sandbox")
local cases = {
  { name = "missing prop chain", src = [[
    local t = { CurrentCamera = nil }
    local cam = __FUHD_SAFE_INDEX__(t, "CurrentCamera")
    local cf = cam.CFrame
    local pos = __FUHD_SAFE_INDEX__(cf, "Position")
    return tostring(pos)
  ]] },
  { name = "nil base chain", src = [[
    local cam = __FUHD_SAFE_INDEX__(nil, "CurrentCamera")
    local cf = cam.CFrame
    local pos = __FUHD_SAFE_INDEX__(cf, "Position")
    return tostring(pos)
  ]] },
  { name = "dot after safe", src = [[
    local t = {}
    local x = __FUHD_SAFE_INDEX__(t, "CurrentCamera").CFrame.Position
    return tostring(x)
  ]] },
  { name = "vm register still nil-like", src = [[
    local L = {}
    local v = __FUHD_SAFE_INDEX__(L, 99)
    -- softNil is truthy; check metamethods instead of ==
    if v then
      local w = v + 1
      return "soft:" .. tostring(w)
    end
    return "nil"
  ]] },
}
for _, c in ipairs(cases) do
  local r = Sandbox.run(c.src, {
    timeout = 5, maxNest = 2, traceLimit = 5000,
    onProgress = function() end, allowHttp = false,
    softInstanceCall = true,
  })
  print(c.name, "err=", tostring(r.err), "res=", tostring(r.results and r.results[1]))
end
