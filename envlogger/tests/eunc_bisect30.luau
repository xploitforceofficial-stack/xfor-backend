local Sandbox = require("../src/core/sandbox")
local result = Sandbox.run([=[
local fn = loadstring("return foo")
local env = { foo = 123 }
setfenv(fn, env)
local r = fn()
print("r type:", type(r), "tostring:", tostring(r))
local rawType = type(r)
print("==123:", rawType == "number" and r == 123, "render:", tostring(r == 123))
]=])
print("ok:", result.ok, "err:", tostring(result.err))
for _, line in ipairs(result.outputs or {}) do print("OUT:", line.text) end
