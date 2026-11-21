local Sandbox = require("../src/core/sandbox")
local src = [[
local ok, err = pcall(coroutine.resume)
print("resume()|", tostring(ok), "|", tostring(err))
local ok2, err2 = pcall(coroutine.resume, 5)
print("resume(5)|", tostring(ok2), "|", tostring(err2))
]]
local ok, res = pcall(Sandbox.run, src, { timeout = 30 })
if not ok then print("sandbox error:", tostring(res):sub(1,300)) return end
print("ok:", res.ok, "err:", res.err)
for _, e in ipairs(res.outputs or {}) do print("OUT|" .. tostring(e.text)) end
