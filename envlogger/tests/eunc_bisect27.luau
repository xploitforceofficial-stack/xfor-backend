local Sandbox = require("../src/core/sandbox")
local result = Sandbox.run([=[
local env = { bar = "works" }
local fn = loadstring("print(bar)")
setfenv(fn, env)
local ok, err = pcall(function() return fn() end)
print("case1 fn call:", ok, err)
local fn2 = loadstring("return bar")
setfenv(fn2, env)
local ok2, r2 = pcall(fn2)
print("case2 return bar:", ok2, r2)
local fn3 = loadstring("return bar")
setfenv(fn3, { bar = "iso" })
print("case3 isolated:", fn3())
local fn4 = loadstring("leaked = true")
setfenv(fn4, { leaked = true })
pcall(fn4)
print("case4 leak:", leaked)
]=])
print("sandbox ok:", result.ok)
if not result.ok then print("ERR:", tostring(result.err)) end
for _, line in ipairs(result.outputs or {}) do
	if type(line) == "table" then print("OUT:", line.text) else print("OUT:", tostring(line)) end
end
