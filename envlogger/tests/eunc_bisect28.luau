local Sandbox = require("../src/core/sandbox")
local result = Sandbox.run([=[
local env = { bar = "works" }
local fn = loadstring("print(bar)")
local before = getfenv(fn)
print("before, bar =", tostring(before and before.bar))
setfenv(fn, env)
local after = getfenv(fn)
print("after: type =", type(after), "bar =", tostring(type(after) == "table" and after.bar or "?"))
local ok, err = pcall(fn)
print("direct call:", ok, err)
]=])
print("ok:", result.ok, "err:", tostring(result.err))
for _, line in ipairs(result.outputs or {}) do print("OUT:", line.text) end
