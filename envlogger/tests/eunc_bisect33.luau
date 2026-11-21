local Sandbox = require("../src/core/sandbox")
local result = Sandbox.run([=[
local fn = loadstring("local e = getfenv(1) print('rawget foo =', rawget(e, 'foo')) return foo")
setfenv(fn, { foo = 123 })
print("call:", fn())
]=])
print("ok:", result.ok, "err:", tostring(result.err))
for _, line in ipairs(result.outputs or {}) do print("OUT:", line.text) end
