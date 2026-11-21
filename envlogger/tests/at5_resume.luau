local Sandbox = require("../src/core/sandbox")
local src = [[
local ok, err = pcall(function() return coroutine.resume() end)
print("resume()|", tostring(ok), "|", tostring(err))
local co = coroutine.create(function() end)
print("resume(co)|", tostring(coroutine.resume(co)))
]]
local ok, res = pcall(Sandbox.run, src, { timeout = 30 })
if not ok then print("sandbox error:", res) return end
for _, e in ipairs(res.outputs or {}) do print("OUT|" .. tostring(e.text)) end
