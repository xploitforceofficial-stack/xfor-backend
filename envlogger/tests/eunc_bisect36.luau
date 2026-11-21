local Sandbox = require("../src/core/sandbox")
local result = Sandbox.run([=[
local fn = loadstring("return foo")
setfenv(fn, { foo = 123 })
print("RESULT:", fn())
]=], { noInstrument = true })
print("ok:", result.ok, "err:", tostring(result.err))
for _, line in ipairs(result.outputs or {}) do print("OUT:", line.text) end
