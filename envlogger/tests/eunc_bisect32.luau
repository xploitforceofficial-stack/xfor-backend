local Sandbox = require("../src/core/sandbox")
local result = Sandbox.run([=[
local fn = loadstring("local e = getfenv(1) local c = 0 for k,v in pairs(e) do c += 1 if c < 8 then print('K:', tostring(k), tostring(v)) end end return foo")
setfenv(fn, { foo = 123 })
local ok, r = pcall(fn)
print("call:", ok, r)
print("type(getfenv(fn)) =", type(getfenv and "n/a"))
]=])
print("ok:", result.ok, "err:", tostring(result.err))
for _, line in ipairs(result.outputs or {}) do print("OUT:", line.text) end
