local Sandbox = require("../src/core/sandbox")
local src = [==[
print("SAFE_INDEX", type(__FUHD_SAFE_INDEX__))
print("SAFE", type(__FUHD_SAFE__))
print("nilPos", tostring(__FUHD_SAFE_INDEX__(nil, "Position")))
print("nilCall", pcall(function() return __FUHD_SAFE__(nil):ToString() end))
]==]
local r = Sandbox.run(src, { timeout = 10, softInstanceCall = true })
print("err", tostring(r.err))
for _, rec in ipairs(r.trace.records) do
  if rec.kind == "output" then print("OUT", tostring(rec.expression)) end
end
