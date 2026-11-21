local Sandbox = require("../src/core/sandbox")
local result = Sandbox.run([=[
local fn = loadstring("return foo")
print("setfenv is:", tostring(setfenv))
local e = { foo = 123 }
local r = setfenv(fn, e)
print("returned fn is same:", r == fn, "tostring r:", tostring(r))
print("after getfenv type:", type(getfenv(fn) == nil and "err" or "t"))
local ge = (function() local ok, v = pcall(getfenv, fn) if ok then return v else return nil end end)()
if type(ge) == "table" then
	print("ge.foo =", tostring(ge.foo), "rawget:", tostring(rawget(ge, "foo")))
else
	print("ge:", tostring(ge))
end
]=])
print("ok:", result.ok, "err:", tostring(result.err))
for _, line in ipairs(result.outputs or {}) do print("OUT:", line.text) end
