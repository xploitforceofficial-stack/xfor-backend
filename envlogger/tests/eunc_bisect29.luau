local Sandbox = require("../src/core/sandbox")
local result = Sandbox.run([=[
local fn = loadstring("print(bar)")
print("type(fn) =", type(fn))
local ok, err = pcall(setfenv, fn, { bar = "works" })
print("setfenv pcall:", ok, err)
]=])
print("ok:", result.ok, "err:", tostring(result.err))
for _, line in ipairs(result.outputs or {}) do print("OUT:", line.text) end
