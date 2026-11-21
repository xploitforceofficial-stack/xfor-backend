local Sandbox = require("../src/core/sandbox")
local result = Sandbox.run([=[
local fn = loadstring("return 42")
local env = { foo = 123 }
local mt = getmetatable(env)
print("plain table mt:", tostring(mt))
local e2 = setmetatable({}, { __index = function(_, k) if k == "zz" then return 7 end end })
print("e2 mt is fn:", type(getmetatable(e2)) == "table")
local f2 = loadstring("return 1")
setfenv(f2, e2)
print("setfenv with metatable'd env ok")
]=])
print("ok:", result.ok, "err:", tostring(result.err))
for _, line in ipairs(result.outputs or {}) do print("OUT:", line.text) end
