local Sandbox = require("../src/core/sandbox")
local result = Sandbox.run([=[
local fn = loadstring("return foo")
print("type fn:", type(fn), "isclosure-ish:", tostring(getmetatable(fn) ~= nil))
local env = { foo = 123 }
setfenv(fn, env)
print("env table mt after setfenv:", tostring(getmetatable(env)))
print("RESULT:", fn())
]=])
print("ok:", result.ok, "err:", tostring(result.err))
for _, line in ipairs(result.outputs or {}) do print("OUT:", line.text) end
